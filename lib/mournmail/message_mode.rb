require "uri"
require "mime/types"

using Mournmail::MessageRendering

module Mournmail
  class MessageMode < Textbringer::Mode
    MESSAGE_MODE_MAP = Keymap.new
    MESSAGE_MODE_MAP.define_key("\C-m", :message_open_link_or_part_command)
    MESSAGE_MODE_MAP.define_key("s", :message_save_part_command)
    MESSAGE_MODE_MAP.define_key("\t", :message_next_link_or_part_command)

    # See http://nihongo.jp/support/mail_guide/dev_guide.txt
    MAILTO_REGEXP = URI.regexp("mailto")
    URI_REGEXP = /(https?|ftp):\/\/[^ 　\t\n>)"]*[^\] 　\t\n>.,:)"]+|#{MAILTO_REGEXP}/
    MIME_REGEXP = /^\[(([0-9.]+) [A-Za-z._\-]+\/[A-Za-z._\-]+.*|PGP\/MIME .*)\]$/
    URI_OR_MIME_REGEXP = /#{URI_REGEXP}|#{MIME_REGEXP}/

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :mime_part, MIME_REGEXP
    define_syntax :link, URI_REGEXP

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MESSAGE_MODE_MAP
      @attached_file = nil
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

    define_local_command(:message_next_link_or_part,
                         doc: "Go to the next link or MIME part.") do
      if @buffer.looking_at?(URI_OR_MIME_REGEXP)
        @buffer.forward_char
      end
      if @buffer.re_search_forward(URI_OR_MIME_REGEXP, raise_error: false)
        goto_char(@buffer.match_beginning(0))
      else
        @buffer.beginning_of_buffer
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
        (part["content-disposition"]&.parameters&.[]("filename") rescue nil) ||
        (part["content-type"]&.parameters&.[]("name") rescue nil) ||
        part_default_file_name(part)
      decoded_file_name = Mail::Encodings.decode_encode(file_name, :decode)
      if /\A([A-Za-z0-9_\-]+)'(?:[A-Za-z0-9_\-])*'(.*)/ =~ decoded_file_name
        $2.encode("utf-8", $1)
      else
        decoded_file_name
      end
    end

    def part_default_file_name(part)
      base_name =
        begin
          part.cid.gsub(/[^A-Za-z0-9_\-]/, "_")
        rescue NoMethodError
          "mournmail"
        end
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
      if part.main_type != "text" || part.sub_type == "html"
        if ext.nil?
          raise EditorError, "The extension of the filename is not specified"
        end
        if !CONFIG[:mournmail_allowed_attachment_extensions].include?(ext)
          raise EditorError, ".#{ext} is not allowed"
        end
      end
      if ext
        file_name = ["mournmail", "." + ext]
      else
        file_name = "mournmail"
      end
      @attached_file = Tempfile.open(file_name, binmode: true)
      s = part.decoded
      if part.content_type == "text/html"
        s = s.sub(/<meta http-equiv="content-type".*?>/i, "")
      elsif part.charset
        s = s.encode(part.charset)
      end
      @attached_file.write(s)
      @attached_file.close
      if part.main_type == "text" && part.sub_type != "html"
        find_file(@attached_file.path)
      else
        background do
          system(*CONFIG[:mournmail_file_open_comamnd], @attached_file.path,
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
