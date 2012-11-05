require 'rubygems'
require 'asciidoctor'

#lines = File.readlines("test/fixtures/asciidoc_index.txt")
#lines = File.read("test/fixtures/asciidoc_index.txt")
doc = Asciidoctor::Document.new("*This* is it.")
puts doc.render