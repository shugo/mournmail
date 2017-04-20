# frozen_string_literal: true

module Textbringer
  CONFIG[:mournmail_directory] = File.expand_path("~/.mournmail")
  CONFIG[:mournmail_from] = ""
  CONFIG[:mournmail_delivery_method] = :smtp
  CONFIG[:mournmail_delivery_options] = {}
  CONFIG[:mournmail_charset] = "utf-8"
end
