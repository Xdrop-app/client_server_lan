part of 'basenode.dart';

/// The Node for if the device is to act as a server (i.e connect to all the clients). It can communicate with all the clients it's connected to.
class ServerNode extends _BaseServerNode {
  ServerNode(
      {required this.name,
      this.host,
      this.port = 8084,
      this.verbose = false,
      this.platform}) {
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

  /// Used to setup the Node ready for use
  Future<void> init({String? ip, bool start = true}) async {
    var _h = ip;
    _h ??= host;
    _h ??= await _getHost();
    if (_h != null) {
      await _initServerNode(_h, start: start);
    }
  }
}

abstract class _BaseServerNode extends _BaseNode {
  BaseServerNode() {
    _isServer = true;
  }

  List<ConnectedClientNode> get clientsConnected => _clients;

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
    final subnet = _subnetBroadcast(host!);

    // Use a fresh ephemeral socket for each broadcast.
    // A persistent socket accumulates ICMP Port Unreachable errors sent back
    // by other devices on the subnet that have nothing listening on port 9104.
    // On iOS this poisons the socket — send() returns 0 for all subsequent calls.
    // A short-lived socket is closed before ICMP errors are delivered to it.
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        ..broadcastEnabled = true;
      sock.send(data, InternetAddress('255.255.255.255'), 9104);
      if (subnet != '255.255.255.255') {
        sock.send(data, InternetAddress(subnet), 9104);
      }
    } catch (_) {}
    sock?.close();

    if (verbose) {
      print("Broadcasting to 255.255.255.255 and $subnet: $payload");
    }
  }

  /// Returns the /24 directed broadcast for the given IP.
  /// e.g. "192.168.1.7" → "192.168.1.255"
  String _subnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    }
    return '255.255.255.255';
  }

  void _evictStaleDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    _clients.removeWhere((c) => c.lastSeen?.isBefore(cutoff) ?? true);
  }
}
