part of 'basenode.dart';

/// The Node for if the device is to act as a server (i.e connect to all the clients). It can communicate with all the clients it's connected to.
class ServerNode extends _BaseServerNode {
  ServerNode(
      {required this.name,
      this.host,
      this.port = 8084,
      this.verbose = false,
      this.platform,
      this.broadcastAddresses = const <String>[]}) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (host == null) {
        throw ArgumentError("Please provide a host for the node");
      }
    }
  }

  @override
  String name;

  @override
  String? platform;

  /// The IP address of the device
  @override
  String? host;

  /// The Port to use for communication
  @override
  int port;

  /// Whether to debug print outputs of what's happening
  @override
  bool verbose;

  /// Optional exact broadcast addresses for the active LAN interface(s).
  ///
  /// Dart's NetworkInterface API does not expose subnet masks on all platforms,
  /// so callers with native interface metadata can pass the precise addresses
  /// here. Discovery still sends to limited broadcast and common subnet
  /// candidates when this list is empty.
  final List<String> broadcastAddresses;

  /// Used to setup the Node ready for use
  Future<void> init({String? ip, bool start = true}) async {
    var _h = ip;
    _h ??= host;
    _h ??= await _getHost();
    await _initServerNode(_h, start: start);
  }
}

abstract class _BaseServerNode extends _BaseNode {
  _BaseServerNode() {
    _isServer = true;
  }

  List<ConnectedClientNode> get clientsConnected => _clients;

  List<String> get broadcastAddresses;

  /// Used to scan for client Nodes
  Future<void> discoverNodes() async => _broadcastForDiscovery();

  Future<void> _initServerNode(String host, {required bool start}) async {
    await _initNode(host, true, start: start);
    if (verbose) {
      _.ok(_e.nodeReady);
    }
    _readyCompleter.complete();
  }

  /// retrurns whether the client of name has been discovered
  bool hasClient(String name) {
    for (final client in _clients) {
      if (client.name == name) {
        return true;
      }
    }
    return false;
  }

  /// Gets the IP address of a discovered client from their name
  String? clientUri(String name) {
    String? addr;
    for (final client in _clients) {
      if (client.name == name) {
        addr = client.address;
        break;
      }
    }
    return addr;
  }

  Future<void> _broadcastForDiscovery() async {
    await _socketReady.future;
    _evictStaleDevices();
    final payload = DataPacket(
            host: host!,
            port: port,
            name: name,
            title: "client_connect",
            platform: platform ?? '')
        .encodeToString();
    final data = utf8.encode(payload);
    final targets = _broadcastTargets(host!, broadcastAddresses);

    // Use a fresh ephemeral socket for each broadcast.
    // A persistent socket accumulates ICMP Port Unreachable errors sent back
    // by other devices on the subnet that have nothing listening on port 9104.
    // On iOS this poisons the socket — send() returns 0 for all subsequent calls.
    // A short-lived socket is closed before ICMP errors are delivered to it.
    RawDatagramSocket? sock;
    try {
      if (InternetAddress.tryParse(host!)?.type == InternetAddressType.IPv6) {
        sock = await RawDatagramSocket.bind(InternetAddress.anyIPv6, 0);
        sock.send(data, InternetAddress('ff02::1'), 9104);
      } else {
        sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
          ..broadcastEnabled = true;
        for (final target in targets) {
          sock.send(data, InternetAddress(target), 9104);
        }
      }
    } catch (_) {}
    sock?.close();

    if (verbose) {
      print("Broadcasting to ${targets.join(', ')}: $payload");
    }
  }

  /// Returns a conservative set of broadcast targets for the given IPv4 address.
  ///
  /// Exact directed broadcasts require the interface netmask, which dart:io does
  /// not expose consistently across Android/iOS/Windows. Until callers provide
  /// native broadcast addresses, include limited broadcast plus common LAN subnet
  /// sizes so non-/24 networks such as /23 and /22 are covered.
  Set<String> _broadcastTargets(String ip, List<String> exactAddresses) {
    final targets = <String>{'255.255.255.255'};
    targets.addAll(exactAddresses.where(_isIPv4Address));

    final parts = ip.split('.');
    if (parts.length != 4) return targets;

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return targets;

    final address = octets.fold<int>(0, (value, octet) {
      return (value << 8) | octet!;
    });
    final commonPrefixLengths = <int>{
      if (octets[0] == 10) ...[8, 9, 10, 11, 12, 13, 14, 15],
      if (octets[0] == 10 || octets[0] == 172) 12,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
    };
    for (final prefixLength in commonPrefixLengths) {
      final mask = (0xffffffff << (32 - prefixLength)) & 0xffffffff;
      final broadcast = (address | (~mask & 0xffffffff)) & 0xffffffff;
      targets.add(_ipv4FromInt(broadcast));
    }

    return targets;
  }

  bool _isIPv4Address(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
    }
    return true;
  }

  String _ipv4FromInt(int value) {
    return '${(value >> 24) & 0xff}.${(value >> 16) & 0xff}.'
        '${(value >> 8) & 0xff}.${value & 0xff}';
  }

  void _evictStaleDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    _clients.removeWhere((c) => c.lastSeen?.isBefore(cutoff) ?? true);
  }
}
