private void print(OutputStream stream, int indent, string format, ...) {
  var indent_str = string.nfill(indent, '\t');
  var message = format.vprintf(va_list());
  stream.printf(null, null, "%s%s", indent_str, message); 
}

private void write_description(OutputStream stream, int indent, Description? description, string? summary=null) {
  string comment = null;
  if(description == null) {
    comment = summary;
  }
  else {
    comment = description.description ?? description.summary;
  }
  if(comment == null) return;
  var lines = comment.strip().split("\n");
  print(stream, indent, "/**\n");
  foreach(unowned string l in lines) {
    print(stream, indent, " * %s\n", l.strip());
  }
  print(stream, indent, " */\n");
}

private void write_version(OutputStream stream, int indent, int since=-1, int deprecated=-1) {
  if(since == -1 && deprecated == -1) return;
  string since_version = since > 0 ? "since=\"%d\"".printf(since) : "";
  string deprecated_version = deprecated > 0 ? "deprecated=true, deprecated_since=\"%d\"".printf(deprecated) : "";
  print(stream, indent, "[Version (%s%s%s)]\n", since_version, since_version != "" && deprecated_version != "" ? ", " : "", deprecated_version);
}
