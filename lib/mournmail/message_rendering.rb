require "mail"
require "html2text"

module Mournmail
  module MessageRendering
    refine ::Mail::Message do
      def render(indices = [])
        render_header + "\n" + render_body(indices)
      end

      def render_header
        CONFIG[:mournmail_display_header_fields].map { |name|
          val = self[name]&.to_s&.gsub(/\t/, " ")
          val ? "#{name}: #{val}\n" : ""
        }.join
      end        

      def render_body(indices = [])
        if HAVE_MAIL_GPG && encrypted?
          mail = decrypt(verify: true)
          if mail.signatures.empty?
            sig = ""
          else
            sig = "[PGP/MIME signature]\n" +
              signature_of(mail)
          end
          return "[PGP/MIME encrypted message]\n" + mail.render(indices) + sig
        end
        if multipart?
          parts.each_with_index.map { |part, i|
            no_content = sub_type == "alternative" && i > 0
            part.render([*indices, i], no_content)
          }.join
        elsif main_type.nil? || main_type == "text"
          s = Mournmail.to_utf8(body.decoded, charset)
          if sub_type == "html"
            "[0 text/html]\n" + Html2Text.convert(s)
          else
            s
          end
        else
          type = Mail::Encodings.decode_encode(self["content-type"].to_s,
                                               :decode) rescue
          "broken/type; error=\"#{$!} (#{$!.class})\""
          "[0 #{type}]\n"
        end + pgp_signature
      end

      def dig_part(i, *rest_indices)
        if HAVE_MAIL_GPG && encrypted?
          mail = decrypt(verify: true)
          return mail.dig_part(i, *rest_indices)
        end
        if i == 0
          return self
        end
        part = parts[i - 1]
        if rest_indices.empty?
          part
        else
          part.dig_part(*rest_indices)
        end
      end

      private

      def pgp_signature 
        if HAVE_MAIL_GPG && signed?
          verified = verify
          signature_of(verified)
        else
          ""
        end
      end

      def signature_of(m)
        validity = m.signature_valid? ? "Good" : "Bad"
        from = m.signatures.map { |sig|
          sig.from rescue sig.fingerprint
        }.join(", ")
        s = "#{validity} signature from #{from}"
        message(s)
        s + "\n"
      end
    end

    refine ::Mail::Part do
      def render(indices, no_content = false)
        index = indices.map { |i| i + 1 }.join(".")
        type = Mail::Encodings.decode_encode(self["content-type"].to_s,
                                             :decode) rescue
          "broken/type; error=\"#{$!} (#{$!.class})\""
        "[#{index} #{type}]\n" +
          render_content(indices, no_content)
      end

      def dig_part(i, *rest_indices)
        if main_type == "message" && sub_type == "rfc822"
          mail = Mail.new(body.to_s)
          mail.dig_part(i, *rest_indices)
        else
          part = parts[i - 1]
          if rest_indices.empty?
            part
          else
            part.dig_part(*rest_indices)
          end
        end
      end

      private

      def render_content(indices, no_content)
        if multipart?
          parts.each_with_index.map { |part, i|
            part.render([*indices, i],
                        no_content || sub_type == "alternative" && i > 0)
          }.join
        else
          return "" if no_content
          if main_type == "message" && sub_type == "rfc822"
            mail = Mail.new(body.raw_source)
            mail.render(indices)
          elsif attachment?
            ""
          else
            if main_type == "text"
              if sub_type == "html"
                Html2Text.convert(decoded).sub(/(?<!\n)\z/, "\n")
              else
                decoded.sub(/(?<!\n)\z/, "\n").gsub(/\r\n/, "\n")
              end
            else
              ""
            end
          end
        end
      rescue => e
        "Broken part: #{e} (#{e.class})"
      end
    end
  end
end
