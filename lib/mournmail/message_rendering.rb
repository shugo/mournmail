# frozen_string_literal: true

require "mail"

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
            part.render([*indices, i])
          }.join
        else
          s = body.decoded
          Mournmail.to_utf8(s, charset)
        end + pgp_signature
      end

      def dig_part(i, *rest_indices)
        if HAVE_MAIL_GPG && encrypted?
          mail = decrypt(verify: true)
          return mail.dig_part(i, *rest_indices)
        end
        part = parts[i]
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
      def render(indices)
        index = indices.join(".")
        type = Mail::Encodings.decode_encode(self["content-type"].to_s,
                                             :decode) rescue
          "broken/type; error=\"#{$!} (#{$!.class})\""
        "[#{index} #{type}]\n" + render_content(indices)
      end

      def dig_part(i, *rest_indices)
        if main_type == "message" && sub_type == "rfc822"
          mail = Mail.new(body.to_s)
          mail.dig_part(i, *rest_indices)
        else
          part = parts[i]
          if rest_indices.empty?
            part
          else
            part.dig_part(*rest_indices)
          end
        end
      end

      private

      def render_content(indices)
        if multipart?
          parts.each_with_index.map { |part, i|
            part.render([*indices, i])
          }.join
        elsif main_type == "message" && sub_type == "rfc822"
          mail = Mail.new(body.raw_source)
          mail.render(indices)
        elsif attachment?
          ""
        else
          if main_type == "text" && sub_type == "plain"
            decoded.sub(/(?<!\n)\z/, "\n").gsub(/\r\n/, "\n")
          else
            ""
          end
        end
      rescue => e
        "Broken part: #{e} (#{e.class})"
      end
    end
  end
end
