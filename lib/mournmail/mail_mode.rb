module Mournmail
  class MailMode < Textbringer::Mode
    MAIL_MODE_MAP = Keymap.new
    MAIL_MODE_MAP.define_key("\C-c\C-c", :mail_send)

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MAIL_MODE_MAP
    end
  end
end
