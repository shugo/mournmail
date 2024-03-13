# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mournmail/version'

Gem::Specification.new do |spec|
  spec.name          = "mournmail"
  spec.version       = Mournmail::VERSION
  spec.authors       = ["Shugo Maeda"]
  spec.email         = ["shugo@ruby-lang.org"]

  spec.summary       = "A message user agent for Textbringer."
  spec.description   = "A message user agent for Textbringer."
  spec.homepage      = "https://github.com/shugo/mournmail"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "textbringer"
  spec.add_runtime_dependency "net-smtp"
  spec.add_runtime_dependency "net-imap", ">= 0.3.1"
  spec.add_runtime_dependency "mail"
  spec.add_runtime_dependency "mime-types"
  spec.add_runtime_dependency "rroonga"
  spec.add_runtime_dependency "google-apis-core"
  spec.add_runtime_dependency "launchy"
  spec.add_runtime_dependency "nokogiri"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", ">= 12.0"
end
