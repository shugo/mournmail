module Textbringer
  Face.define :seen, inherit: :comment
  Face.define :deleted, inherit: :string
  Face.define :answered, inherit: :number
  Face.define :unseen, bold: true
  Face.define :flagged, foreground: "yellow", bold: true
  Face.define :field_name, inherit: :function_name
  Face.define :quotation, inherit: :comment
  Face.define :header_end, inherit: :property
  Face.define :mime_part, inherit: :link, bold: true, underline: false
end
