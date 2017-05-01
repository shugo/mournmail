# frozen_string_literal: true

using Mournmail::MessageRendering

module Mournmail
  class MessageMode < Textbringer::Mode
    MESSAGE_MODE_MAP = Keymap.new
    MESSAGE_MODE_MAP.define_key("s", :message_save_part_command)

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :mime_part, /^\[([0-9.]+) [A-Za-z._\-]+\/[A-Za-z._\-]+.*\]$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MESSAGE_MODE_MAP
    end

    define_local_command(:message_save_part, doc: "Save the current part.") do
      @buffer.save_excursion do
        @buffer.beginning_of_line
        if @buffer.looking_at?(/\[([0-9.]+) .*\]/)
          index = match_string(1)
          indices = index.split(".").map(&:to_i)
          part = Mournmail.current_mail.dig_part(*indices)
          default_name =
            part["content-disposition"]&.parameters&.[]("filename") ||
            part["content-type"]&.parameters&.[]("name") ||
            Mournmail.current_uid.to_s + "-" + index
          decoded_name = Mail::Encodings.decode_encode(default_name, :decode)
          if /\A([A-Za-z0-9_\-]+)'(?:[A-Za-z0-9_\-])*'(.*)/ =~ decoded_name
            decoded_name = $2.encode("utf-8", $1)
          end
          default_path = File.expand_path(decoded_name,
                                          CONFIG[:mournmail_save_directory])
          path = read_file_name("Save: ", default: default_path)
          if !File.exist?(path) || yes_or_no?("File exists; overwrite?")
            File.write(path, part.decoded)
          end
        end
      end
    end
  end
end
