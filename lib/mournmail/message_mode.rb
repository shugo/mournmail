# frozen_string_literal: true

require "uri"
require "mime/types"

using Mournmail::MessageRendering

module Mournmail
  class MessageMode < Textbringer::Mode
    MESSAGE_MODE_MAP = Keymap.new
    MESSAGE_MODE_MAP.define_key("\C-m", :message_open_link_or_part_command)
    MESSAGE_MODE_MAP.define_key("s", :message_save_part_command)

    # See http://nihongo.jp/support/mail_guide/dev_guide.txt
    MAILTO_REGEXP = URI.regexp("mailto")
    URI_REGEXP = /(https?|ftp):\/\/[^ 　\t\n>)"]*[^] 　\t\n>.,:)"]+|#{MAILTO_REGEXP}/

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :mime_part,
      /^\[(([0-9.]+) [A-Za-z._\-]+\/[A-Za-z._\-]+.*|PGP\/MIME .*)\]$/
    define_syntax :link, URI_REGEXP

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MESSAGE_MODE_MAP
    end

    define_local_command(:message_open_link_or_part,
                         doc: "Open a link or part.") do
      part = current_part
      if part
        open_part(part)
      else
        uri = current_uri
        if uri
          open_uri(uri)
        end
      end
    end

    define_local_command(:message_save_part, doc: "Save the current part.") do
      part = current_part
      return if part.nil?
      default_path = File.expand_path(part_file_name(part),
                                      CONFIG[:mournmail_save_directory])
      path = read_file_name("Save: ", default: default_path)
      if !File.exist?(path) || yes_or_no?("File exists; overwrite?")
        File.write(path, part.decoded)
      end
    end

    private

    def current_part
      @buffer.save_excursion do
        @buffer.beginning_of_line
        if @buffer.looking_at?(/\[([0-9.]+) .*\]/)
          index = match_string(1)
          indices = index.split(".").map(&:to_i)
          @buffer[:mournmail_mail].dig_part(*indices)
        else
          nil
        end
      end
    end

    def part_file_name(part)
      file_name =
        part["content-disposition"]&.parameters&.[]("filename") ||
        part["content-type"]&.parameters&.[]("name") ||
        part_default_file_name(part)
      decoded_file_name = Mail::Encodings.decode_encode(file_name, :decode)
      if /\A([A-Za-z0-9_\-]+)'(?:[A-Za-z0-9_\-])*'(.*)/ =~ decoded_file_name
        $2.encode("utf-8", $1)
      else
        decoded_file_name
      end
    end

    def part_default_file_name(part)
      base_name = part.cid.gsub(/[^A-Za-z0-9_\-]/, "_")
      ext = part_extension(part)
      if ext
        base_name + "." + ext
      else
        base_name
      end
    end

    def part_extension(part)
      mime_type = part["content-type"].string
      MIME::Types[mime_type]&.first&.preferred_extension
    end

    def current_uri
      @buffer.save_excursion do
        pos = @buffer.point
        @buffer.beginning_of_line
        pos2 = @buffer.re_search_forward(URI_REGEXP, raise_error: false)
        if pos2 && match_beginning(0) <= pos && pos < match_end(0)
          match_string(0)
        else
          nil
        end
      end
    end

    def open_part(part)
      if part.multipart?
        raise EditorError, "Can't open a multipart entity."
      end
      ext = part_file_name(part).slice(/\.([^.]+)\z/, 1)
      if ext
        file_name = ["mournmail", "." + ext]
      else
        file_name = "mournmail"
      end
      f = Tempfile.open(file_name)
      f.write(part.decoded)
      f.close
      if ext == "txt"
        find_file(f.path)
      else
        background do
          system(*CONFIG[:mournmail_file_open_comamnd], f.path,
                 out: File::NULL, err: File::NULL)
        end
      end
    end

    def open_uri(uri)
      case uri
      when /\Amailto:/
        u = URI.parse(uri)
        if u.headers.assoc("subject")
          re = /^To:\s*\nSubject:\s*\n/
        else
          re = /^To:\s*\n/
        end
        Commands.mail
        beginning_of_buffer
        re_search_forward(re)
        replace_match("")
        insert u.to_mailtext.sub(/\n\n\z/, "")
        end_of_buffer
      else
        system(*CONFIG[:mournmail_link_open_comamnd], uri,
               out: File::NULL, err: File::NULL)
      end
    end
  end
end
