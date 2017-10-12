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
        line = String.new
        fold_line = false
        while !fold_line && !words.empty?
          word = words.first
          s = (line.empty? ? "" : " ").dup
          if word.ascii_only?
            s << word
            break if !line.empty? && line.bytesize + s.bytesize > limit
            words.shift
          else
            words.shift
            encoded_text = Mail::Encodings::Base64.encode(word).chomp
            min_size = line.bytesize + s.bytesize + b_encoding_extra_size
            new_size = min_size + encoded_text.bytesize
            if new_size > limit
              n = (((limit - min_size) * 3.0 / 4.0) / 3.0).floor
              break if n <= 0
              word, rest = word.scan(/\A.{#{n}}|.+/)
              words.unshift(rest) if rest
              encoded_text = Mail::Encodings::Base64.encode(word).chomp
              fold_line = true
            end
            encoded_word = "=?#{charset}?B?#{encoded_text}?="
            s << encoded_word
          end
          line << s
        end
        folded_lines << line
        prepend = 0
      end
      folded_lines
    end
  end
end

Mail::UnstructuredField.prepend(Mournmail::MailEncodedWordPatch)
