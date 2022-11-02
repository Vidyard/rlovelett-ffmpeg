# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require "ffmpeg/version"

Gem::Specification.new do |s|
  s.name        = "rlovelett-ffmpeg"
  s.version     = FFMPEG::VERSION
  s.authors     = ["David Backeus", "Ryan Lovelett"]
  s.email       = ["david@streamio.com", "ryan@lovelett.me"]
  s.homepage    = "http://github.com/RLovelett/rlovelett-ffmpeg"

  s.summary     = "Wraps ffmpeg to read metadata and transcodes videos."

  s.add_dependency "rake", ">= 12.3.3"
  s.add_dependency('multi_json', '~> 1.8')
  s.add_dependency('posix-spawn', '~> 0.3.13')

  s.add_development_dependency("rspec", "~> 2.14.0")
  s.add_development_dependency("rake", "~> 10.1.0")
  s.add_development_dependency("codeclimate-test-reporter", "~> 0.4.7")

  s.files        = Dir.glob("lib/**/*") + %w(README.md LICENSE CHANGELOG)
end
