# frozen_string_literal: true

require "mail"
require "mail-iso-2022-jp"

module Mournmail
  module MessageRendering
    refine ::Mail::Message do
      def render(indices = [])
        render_header + "\n" + render_body(indices)
      end

      def render_header
        CONFIG[:mournmail_display_header_fields].map { |name|
          val = self[name]
          val ? "#{name}: #{val}\n" : ""
        }.join
      end        

      def render_body(indices = [])
        if HAVE_MAIL_GPG && encrypted?
          mail = decrypt(verify: true)
          return mail.render_body(indices)
        end
        if multipart?
          parts.each_with_index.map { |part, i|
            part.render([*indices, i])
          }.join
        else
          s = body.decoded
          if /\Autf-8\z/i =~ charset
            force_utf8(s)
          else
            begin
              s.encode(Encoding::UTF_8, charset, replace: "?")
            rescue Encoding::ConverterNotFoundError
              force_utf8(s)
            end
          end.gsub(/\r\n/, "\n")
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

      def force_utf8(s)
        s.force_encoding(Encoding::UTF_8).scrub("?")
      end

      def pgp_signature 
        if HAVE_MAIL_GPG && signed?
          verified = verify
          validity = verified.signature_valid? ? "Good" : "Bad"
          from = verified.signatures.map { |sig|
            sig.from rescue sig.fingerprint
          }.join(", ")
          "#{validity} signature from #{from}\n"
        else
          ""
        end
      end
    end

    refine ::Mail::Part do
      def render(indices)
        index = indices.join(".")
        type = Mail::Encodings.decode_encode(self["content-type"].to_s,
                                             :decode)
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
        elsif self["content-disposition"]&.disposition_type == "attachment"
          ""
        else
          if main_type == "text" && sub_type == "plain"
            decoded.sub(/(?<!\n)\z/, "\n").gsub(/\r\n/, "\n")
          else
            ""
          end
        end
      end
    end
  end
end
