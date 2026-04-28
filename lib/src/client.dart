part of 'basenode.dart';

/// The Node for if the device is to act as a client (i.e wait for server to connect to it). It can only communicate with the server. Additional work needs to be added in order to facilitate data forwarding.
class ClientNode extends _BaseClientNode {
  ClientNode(
      {required this.name,
      this.host,
      this.port = 8084,
      this.verbose = false,
      this.platform,
      this.version}) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (host == null) {
        throw ArgumentError("Please provide a host");
      }
    }
  }

  @override
  String name;

  /// The name of the node on the network
  @override
  String? platform;

  /// The IP address of the device
  int? version;

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
    ip ??= host;
    ip ??= await _getHost();
    await _initClientNode(ip, start: start);
  }
}

abstract class _BaseClientNode extends _BaseNode {
  _BaseClientNode() {
    _isServer = false;
  }

  ConnectedClientNode? _server;

  /// Provides information about the server if one is connected
  ConnectedClientNode? get serverDetails => _server;

  Future<void> _initClientNode(String host, {required bool start}) async {
    await _initNode(host, false, start: start);
    await _listenForDiscovery();
    if (verbose) {
      _.ok(_e.nodeReady);
    }
    _readyCompleter.complete();
  }

  Future<void> _listenForDiscovery() async {
    await _socketReady.future;
    if (verbose) {
      print("Listening on socket ${_socket.address.host}:$_socketPort");
    }
    _socket.listen((RawSocketEvent e) async {
      final d = _socket.receive();
      if (d == null) {
        return;
      }
      final data = _parseDiscoveryPacket(d.data);
      if (data == null) {
        return;
      }
      _server = ConnectedClientNode(
          address: lanAuthority(data.host, data.port),
          name: data.name,
          platform: data.platform,
          version: data.version,
          lastSeen: DateTime.now());
      if (verbose) {
        print(
            "Recieved connection request from Client ${data.host}:${data.port}");
      }
      final String addr = lanAuthority(data.host, data.port);
      await _sendInfo("client_connect", addr);
    });
  }

  _DiscoveryPacket? _parseDiscoveryPacket(List<int> data) {
    dynamic decoded;
    try {
      decoded = json.decode(utf8.decode(data).trim());
    } catch (e) {
      if (verbose) {
        print("Ignoring malformed discovery packet: $e");
      }
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['title'] != 'client_connect') return null;

    final host = decoded['host']?.toString();
    final port = decoded['port'] is int
        ? decoded['port'] as int
        : int.tryParse(decoded['port']?.toString() ?? '');
    if (host == null || host.isEmpty || port == null) return null;

    return _DiscoveryPacket(
      host: host,
      port: port,
      name: decoded['name']?.toString() ?? '',
      platform: decoded['platform']?.toString(),
      version: decoded['version'] is int
          ? decoded['version'] as int
          : int.tryParse(decoded['version']?.toString() ?? ''),
    );
  }
}

class _DiscoveryPacket {
  _DiscoveryPacket({
    required this.host,
    required this.port,
    required this.name,
    this.platform,
    this.version,
  });

  final String host;
  final int port;
  final String name;
  final String? platform;
  final int? version;
}
