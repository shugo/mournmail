module Mournmail
  # The maximum line length recommended by RFC 5322 (2.1.1), excluding CRLF.
  HEADER_MAX_LINE_LENGTH = 78

  # Unfold a header field body (RFC 5322 2.2.3): remove each CRLF (or LF)
  # that is immediately followed by whitespace, leaving the whitespace.
  def self.unfold_header_value(value)
    value.to_s.gsub(/\r?\n(?=[ \t])/, "")
  end

  # Return "#{name}: #{value}" folded so that each line is not longer than
  # max_line_length characters whenever possible (RFC 5322 2.2.3).
  #
  # Folding only happens at existing whitespace, and the whitespace is
  # preserved at the beginning of the continuation line, so unfolding the
  # result gives back the original value.  A single token longer than
  # max_line_length is never split; it is put on a line of its own.
  # The first token always stays on the same line as the field name.
  #
  # Lines are separated by "\n"; the mail library converts them into CRLF
  # when the message is sent.
  def self.fold_header_field(name, value,
                             max_line_length: HEADER_MAX_LINE_LENGTH)
    # A newline not followed by whitespace can't appear in a header field
    # body, so treat it as a plain space.
    unfolded = unfold_header_value(value).gsub(/\r?\n/, " ").strip
    lines = []
    line = nil
    unfolded.scan(/([ \t]*)([^ \t]+)/) do |ws, token|
      if line.nil?
        line = "#{name}: #{token}"
      elsif line.size + ws.size + token.size <= max_line_length
        line << ws << token
      else
        lines.push(line)
        line = ws + token
      end
    end
    lines.push(line || "#{name}: ")
    lines.join("\n")
  end
end
