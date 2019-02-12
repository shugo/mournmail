# frozen_string_literal: true

require "mail"

module Mournmail
  module MailEncodedWordPatch
    private

    def fold(prepend = 0) # :nodoc:
      charset = normalized_encoding
      decoded_string = decoded.to_s
      if charset != "UTF-8" ||
          decoded_string.ascii_only? ||
          !decoded_string.respond_to?(:encoding) ||
          decoded_string.encoding != Encoding::UTF_8 ||
          Regexp.new('\p{Han}|\p{Hiragana}|\p{Katakana}') !~ decoded_string
        # Use Q encoding
        return super(prepend)
      end
      words = decoded_string.split(/[ \t]/)
      folded_lines   = []
      b_encoding_extra_size = "=?#{charset}?B??=".bytesize
      while !words.empty?
        limit = 78 - prepend
        line = +""
        fold_line = false
        while !fold_line && !words.empty?
          word = words.first
          s = (line.empty? ? "" : " ").dup
          if word.ascii_only?
            s << word
            break if !line.empty? && line.bytesize + s.bytesize > limit
            words.shift
            if prepend + line.bytesize + s.bytesize > 998
              words.unshift(s.slice!(998 - prepend .. -1))
              fold_line = true
            end
          else
            words.shift
            encoded_text = base64_encode(word)
            min_size = line.bytesize + s.bytesize + b_encoding_extra_size
            new_size = min_size + encoded_text.bytesize
            if new_size > limit
              n = ((limit - min_size) * 3.0 / 4.0).floor
              if n <= 0
                words.unshift(word) if !line.empty?
                break
              end
              truncated = word.byteslice(0, n).scrub("")
              rest = word.byteslice(truncated.bytesize,
                                    word.bytesize - truncated.bytesize)
              words.unshift(rest)
              encoded_text = base64_encode(truncated)
              fold_line = true
            end
            encoded_word = "=?#{charset}?B?#{encoded_text}?="
            s << encoded_word
          end
          line << s
        end
        folded_lines << line
        prepend = 1 # Space will be prepended
      end
      folded_lines
    end

    def base64_encode(word)
      Mail::Encodings::Base64.encode(word).gsub(/[\r\n]/, "")
    end
  end
end

Mail::UnstructuredField.prepend(Mournmail::MailEncodedWordPatch)
