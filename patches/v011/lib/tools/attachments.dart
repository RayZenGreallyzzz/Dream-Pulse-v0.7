enum AttachmentKind { image, video, file }

class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.path,
    required this.name,
  });

  final AttachmentKind kind;
  final String path;
  final String name;

  bool get isImage => kind == AttachmentKind.image;
  bool get isVideo => kind == AttachmentKind.video;
  bool get isFile => kind == AttachmentKind.file;
}

class ToolRunResult {
  const ToolRunResult({
    required this.tool,
    required this.output,
    this.ok = true,
  });

  final String tool;
  final String output;
  final bool ok;
}
