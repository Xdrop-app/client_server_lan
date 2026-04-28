part of 'basenode.dart';

Future<String> _getHost() async {
  return getLanHost();
}

/// A usable local address found on a network interface.
class LanHostCandidate {
  const LanHostCandidate({
    required this.address,
    required this.interfaceName,
    required this.interfaceIndex,
    required this.score,
  });

  final String address;
  final String interfaceName;
  final int interfaceIndex;
  final int score;
}

/// Returns the best local address to advertise to peers on the LAN.
///
/// The selected address is used by peer devices to call back into this node's
/// HTTP server, so VPNs, virtual adapters, loopback, and link-local addresses
/// are intentionally deprioritized or skipped.
Future<String> getLanHost() async {
  final candidates = await getLanHostCandidates();
  if (candidates.isEmpty) return '';
  return candidates.first.address;
}

Future<int> getAvailableLanPort(
  String host, {
  int preferredPort = 8085,
  int maxAttempts = 20,
}) async {
  final bindAddress =
      InternetAddress.tryParse(host)?.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4;

  for (var port = preferredPort; port < preferredPort + maxAttempts; port++) {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(bindAddress, port, v6Only: false);
      return socket.port;
    } catch (_) {
      continue;
    } finally {
      await socket?.close();
    }
  }

  final socket = await ServerSocket.bind(bindAddress, 0, v6Only: false);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Returns usable LAN candidates sorted from most to least likely to work.
Future<List<LanHostCandidate>> getLanHostCandidates() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.any,
  );
  final candidates = <LanHostCandidate>[];

  for (final iface in interfaces) {
    final name = iface.name.toLowerCase();
    if (_isVirtualInterface(name)) continue;

    for (final address in iface.addresses) {
      final ip = address.address;
      if (address.type == InternetAddressType.IPv4 && !_isUsableIPv4(ip)) {
        continue;
      }
      if (address.type == InternetAddressType.IPv6 && !_isUsableIPv6(ip)) {
        continue;
      }

      candidates.add(LanHostCandidate(
        address: ip,
        interfaceName: iface.name,
        interfaceIndex: iface.index,
        score: _interfaceScore(name, ip, address.type),
      ));
    }
  }

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.interfaceIndex.compareTo(b.interfaceIndex);
  });
  return candidates;
}

int _interfaceScore(
    String interfaceName, String ip, InternetAddressType addressType) {
  var score = 0;

  if (addressType == InternetAddressType.IPv4 && _isPrivateIPv4(ip)) {
    score += 1000;
  } else if (addressType == InternetAddressType.IPv4 &&
      _isSharedCarrierIPv4(ip)) {
    score += 500;
  } else if (addressType == InternetAddressType.IPv6 &&
      _isUniqueLocalIPv6(ip)) {
    score += 900;
  } else if (addressType == InternetAddressType.IPv6) {
    score += 700;
  } else {
    score += 100;
  }

  if (_isWifiOrHotspotInterface(interfaceName)) score += 500;
  if (_isEthernetInterface(interfaceName)) score += 400;
  if (_isUsbTetherInterface(interfaceName)) score += 300;

  return score;
}

bool _isUsableIPv4(String ip) {
  final octets = _parseIPv4(ip);
  if (octets == null) return false;

  final first = octets[0];
  final second = octets[1];
  if (first == 0 || first == 127 || first >= 224) return false;
  if (first == 169 && second == 254) return false;
  if (ip == '255.255.255.255') return false;

  return true;
}

bool _isUsableIPv6(String ip) {
  final normalized = ip.toLowerCase().split('%').first;
  if (normalized == '::1' || normalized == '::') return false;
  if (normalized.startsWith('fe80:')) return false;
  if (normalized.startsWith('ff')) return false;
  return normalized.contains(':');
}

bool _isUniqueLocalIPv6(String ip) {
  final normalized = ip.toLowerCase();
  return normalized.startsWith('fc') || normalized.startsWith('fd');
}

bool _isPrivateIPv4(String ip) {
  final octets = _parseIPv4(ip);
  if (octets == null) return false;

  final first = octets[0];
  final second = octets[1];
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

bool _isSharedCarrierIPv4(String ip) {
  final octets = _parseIPv4(ip);
  if (octets == null) return false;
  return octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127;
}

List<int>? _parseIPv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;

  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  return octets;
}

bool _isWifiOrHotspotInterface(String name) {
  return name.contains('wi-fi') ||
      name.contains('wifi') ||
      name.contains('wlan') ||
      name.contains('swlan') ||
      name == 'en0' ||
      name.contains('airport');
}

bool _isEthernetInterface(String name) {
  return name.contains('ethernet') ||
      name.contains('eth') ||
      name.contains('local area') ||
      name.contains('enp') ||
      name.contains('ens');
}

bool _isUsbTetherInterface(String name) {
  return name.contains('usb') ||
      name.contains('rndis') ||
      name.contains('ecm') ||
      name.contains('ncm');
}

bool _isVirtualInterface(String name) {
  const blocked = <String>[
    'awdl',
    'br-',
    'bridge',
    'docker',
    'hyper-v',
    'ipsec',
    'llw',
    'p2p',
    'ppp',
    'stf',
    'tailscale',
    'tap',
    'tun',
    'utun',
    'vbox',
    'vethernet',
    'virtual',
    'vmnet',
    'vmware',
    'vnic',
    'wg',
    'zerotier',
  ];
  return blocked.any(name.contains);
}
