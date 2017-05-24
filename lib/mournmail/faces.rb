# frozen_string_literal: true

module Textbringer
  Face.define :seen, foreground: "blue"
  Face.define :deleted, foreground: "green"
  Face.define :unseen, bold: true
  Face.define :flagged, foreground: "yellow", bold: true
  Face.define :field_name, foreground: "magenta", bold: true
  Face.define :quotation, foreground: "yellow"
  Face.define :header_end, foreground: "yellow"
  Face.define :mime_part, foreground: "blue", bold: true
end
