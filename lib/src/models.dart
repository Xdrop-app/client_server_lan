part of 'basenode.dart';

class ConnectedClientNode {
  ConnectedClientNode(
      {required this.name,
      required this.address,
      this.lastSeen,
      this.platform,
      this.version});

  final String name;
  final String? platform;
  final int? version;
  final String address;
  DateTime? lastSeen;
}

String lanAuthority(String host, int port) {
  final cleanHost = host.trim();
  final withoutBrackets = cleanHost.startsWith('[') && cleanHost.endsWith(']')
      ? cleanHost.substring(1, cleanHost.length - 1)
      : cleanHost;
  if (withoutBrackets.contains(':')) {
    return '[$withoutBrackets]:$port';
  }
  return '$withoutBrackets:$port';
}

String normalizeLanAuthority(String value, {int defaultPort = 8085}) {
  var address = value.trim();
  address = address.replaceFirst(RegExp(r'^https?://'), '');
  address = address.split('/').first;
  if (address.isEmpty) return '';
  if (address.startsWith('[')) return address;

  final colonCount = ':'.allMatches(address).length;
  if (colonCount == 0) return '$address:$defaultPort';
  if (colonCount == 1 && int.tryParse(address.split(':').last) != null) {
    return address;
  }
  return '[$address]:$defaultPort';
}

Uri lanHttpUri(String authority, String path) {
  return Uri(
      scheme: 'http',
      host: _authorityHost(authority),
      port: _authorityPort(authority),
      path: path);
}

String _authorityHost(String authority) {
  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0) return authority.substring(1, end);
  }
  final colon = authority.lastIndexOf(':');
  if (colon > 0) return authority.substring(0, colon);
  return authority;
}

int? _authorityPort(String authority) {
  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    if (end > 0 && authority.length > end + 2) {
      return int.tryParse(authority.substring(end + 2));
    }
    return null;
  }
  final colon = authority.lastIndexOf(':');
  if (colon > 0) return int.tryParse(authority.substring(colon + 1));
  return null;
}

/// The type of data that is sent and received. It includes all the neccessary information for that specific communication. The most useful data is the payload, then packet title and the name/host of the sender.
class DataPacket {
  DataPacket(
      {required this.name,
      required this.host,
      required this.port,
      required this.title,
      required this.platform,
      this.payload});

  DataPacket.fromJson(Map<String, dynamic> json)
      : this.host = json["host"],
        this.port = json["port"] is int
            ? json["port"] as int
            : int.parse(json["port"].toString()),
        this.name = json["name"],
        this.platform = json["platform"],
        this.title = json["title"],
        this.payload = json["payload"];

  /// The IP adress of the sender
  final String host;

  /// The Port being used by the sender (and reciever)
  final int port;

  /// The name of the sender
  final String name;

  final String platform;

  /// The title of the packet
  final String title;

  /// The actual data being ditributed
  final dynamic payload;

  /// Encodes the packet data into a json ready for transmitting
  String encodeToString() => json.encode(<String, dynamic>{
        "host": host,
        "port": port.toString(),
        "name": name,
        "platform": platform,
        "title": title,
        "payload": payload?.toString() ?? "null",
      });

  @override
  String toString() => encodeToString();
}

class FileTransferPayload {
  FileTransferPayload({
    required this.downloadPath,
    required this.fileName,
    required this.fileSize,
  });

  static const String legacySeparator = '.*/.*';

  final String downloadPath;
  final String fileName;
  final int fileSize;

  String encodeToString() => json.encode(<String, dynamic>{
        'downloadPath': downloadPath,
        'fileName': fileName,
        'fileSize': fileSize,
      });

  static FileTransferPayload? tryParse(dynamic payload) {
    if (payload == null) return null;
    final value = payload.toString();

    try {
      final decoded = json.decode(value);
      if (decoded is Map<String, dynamic>) {
        final downloadPath = decoded['downloadPath'] ?? decoded['url'];
        final fileName = decoded['fileName'] ?? decoded['name'];
        final fileSize = decoded['fileSize'] ?? decoded['size'];
        if (downloadPath != null && fileName != null && fileSize != null) {
          return FileTransferPayload(
            downloadPath: downloadPath.toString(),
            fileName: fileName.toString(),
            fileSize: fileSize is int
                ? fileSize
                : int.tryParse(fileSize.toString()) ?? 0,
          );
        }
      }
    } catch (_) {}

    final parts = value.split(legacySeparator);
    if (parts.length < 3) return null;
    return FileTransferPayload(
      downloadPath: parts[0],
      fileName: parts[1],
      fileSize: int.tryParse(parts[2]) ?? 0,
    );
  }
}

Future<HttpResponse> _responseHandler(
    HttpRequest request, IsoLogger log) async {
  final content = await utf8.decoder.bind(request).join();
  dynamic c = content;
  try {
    c = json.decode(c);
  } catch (e) {
    print("Json not decoded: $e");
  }
  if (c is Map<String, dynamic>) {
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    if (remoteAddress != null &&
        (_isUsableIPv4(remoteAddress) || _isUsableIPv6(remoteAddress))) {
      c["host"] = remoteAddress;
    }
  }
  log.push(c);
  request.response.statusCode = HttpStatus.ok;
  return request.response;
}
