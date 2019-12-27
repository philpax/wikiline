# coding: utf-8
require 'parslet'

class WikitextParser < Parslet::Parser
  rule(:spaces) { match('\s').repeat(1) }
  rule(:spaces?) { spaces.maybe }

  rule(:comma) { spaces? >> str(',') >> spaces? }

  rule(:bold_surround) { str("'''") }
  rule(:italic_surround) { str("''") }
  rule(:special_text) { bold_surround | italic_surround }

  rule(:key) { match['[:alnum:]_ '].repeat(1) }
  rule(:text) { (special_text.absent? >> match['[:alnum:] ü/\.\(\),;:&\-–_\?\*\'"%#†\+\~ ']).repeat(1) }

  rule(:link) {
    str('[[') >> spaces? >>
      text.as(:page) >>
      (str('|') >> value.as(:alias)).maybe >>
    spaces? >> str(']]')
  }

  rule(:external_link) {
    str('[') >> spaces? >>
      text.as(:page) >>
      (str(' ').absent? >> any).repeat(1).as(:url) >>
      (str(']').absent? >> any).repeat.maybe.as(:alias) >>
    spaces? >> str(']')
  }

  rule(:image) {
    str('[[File:') >> spaces? >> text.as(:name) >>
      macro_argument.repeat.as(:arguments) >>
    spaces? >> str(']]')
  }

  rule(:macro_argument_key) {
    key.as(:key) >> spaces? >> str('=') >> spaces?
  }

  rule(:macro_argument_value) {
    (value >> spaces?).repeat(1).as(:values)
  }

  rule(:macro_argument) {
    spaces? >> str('|') >> spaces? >>
    (macro_argument_key >> macro_argument_value.maybe | macro_argument_value).maybe
  }

  rule(:macro) {
    str('{{') >> spaces? >> text.as(:name) >> 
      macro_argument.repeat.as(:arguments) >>
    spaces? >> str('}}')
  }

  # Courtesy of the XML example
  rule(:xml_tag) {
    tag(close: false).as(:l) >> (spaces? >> value >> spaces?).repeat(1).as(:v) >> tag(close: true).as(:r) |
    tag(close_end: true).as(:l)
  }

  def tag(opts={})
    close = opts[:close] || false
    close_end = opts[:close_end] || false

    parslet = str('<')
    parslet = parslet >> str('/') if close
    parslet = parslet >> key.as('tag')
    if close_end
      parslet = parslet >> (str('/>').absent? >> any).repeat >> str('/>')
    else
      parslet = parslet >> (str('>').absent? >> any).repeat >> str('>')
    end

    parslet
  end

  def surround_with(start_tag, end_tag = nil)
    end_tag = start_tag if end_tag.nil?
    str(start_tag) >> (str(end_tag).absent? >> any).repeat.as('contents') >> str(end_tag)
  end

  def surround_value_with(start_tag, end_tag = nil)
    end_tag = start_tag if end_tag.nil?
    start_tag >> value.repeat.as('contents') >> end_tag
  end

  def xml_self_closing(tag, attributes = false)
    parslet = str('<') >> spaces? >> str(tag) >> spaces?
    if attributes
      parslet = parslet >> (str('/>').absent? >> any).repeat(1)  >> str('/>')
    else
      parslet = parslet >> str('/').maybe >> str('>')
    end
    parslet
  end

  # Special-case ref because we don't care about parsing its contents.
  rule(:ref) {
    surround_with('<ref', '/ref>') | xml_self_closing('ref', true)
  }

  rule(:hr) {
    xml_self_closing('hr')
  }

  rule(:br) {
    xml_self_closing('br')
  }

  rule(:comment) {
    surround_with('<!--', '-->')
  }

  rule(:bold) {
    surround_value_with(bold_surround)
  }

  rule(:italics) {
    surround_value_with(italic_surround)
  }

  rule(:value) {
    comment.as(:comment) |
    ref.as(:ref) |
    hr |
    br |
    xml_tag.as(:xml) |
    macro.as(:macro) |
    image.as(:image) |
    link.as(:link) |
    external_link.as(:external_link) |
    bold.as(:bold) |
    italics.as(:italics) |
    text.as(:text)
  }

  rule(:top) { spaces? >> value >> spaces? }
  root(:top)
end

def pretty_print(tree)
  t = Parslet::Transform.new do
    rule(comment: subtree(:t)) { nil }
    rule(image: subtree(:t)) { nil }
    rule(ref: subtree(:t)) { nil }
    rule(text: simple(:text)) { text.to_s }
    rule(italics: {"contents" => simple(:text)}) { "''#{text.to_s}''" }
    rule(bold: {"contents" => simple(:text)}) { "'''#{text.to_s}'''" }
    rule(link: {page: simple(:page), alias: simple(:alias_name)}) {
      "[[#{page}|#{alias_name}]]"
    }
    rule(link: {page: simple(:page)}) {
      "[[#{page}]]"
    }
    rule(key: simple(:key), values: sequence(:values)) {
      "#{key}=#{values.join(' ')}"
    }
    rule(values: sequence(:values)) {
      values.join(' ')
    }
    rule(macro: {
           name: simple(:name),
           arguments: sequence(:arguments)
         }) {
      s = "{{#{name}"
      separator = name.to_s.downcase.start_with?("infobox ") ? "\n|" : "|"
      s += separator + arguments.join(separator) unless arguments.empty?
      s += "}}"
      s
    }
    rule(xml: {
           l: {"tag" => simple(:tag)},
           r: {"tag" => simple(:tag)},
           v: sequence(:v)
         }) { "<#{tag}>#{v.reject { |a| a.nil? }.join(' ')}</#{tag}>" }
  end

  t.apply(tree)
end

def text_print(tree)
  t = Parslet::Transform.new do
    rule(comment: subtree(:t)) { nil }
    rule(image: subtree(:t)) { nil }
    rule(ref: subtree(:t)) { nil }
    rule(text: simple(:text)) { text.to_s }
    rule(italics: {"contents" => sequence(:values)}) { values.join(" ") }
    rule(bold: {"contents" => sequence(:values)}) { values.join(" ") }
    rule(link: {page: simple(:page), alias: simple(:alias_name)}) {
      alias_name
    }
    rule(link: {page: simple(:page)}) {
      page
    }
    rule(key: simple(:key), values: sequence(:values)) {
      "#{key.to_s.strip}=#{values.join(' ')}"
    }
    rule(key: simple(:key)) {
      "#{key.to_s.strip}="
    }
    rule(values: sequence(:values)) {
      values.join(' ')
    }
    rule(macro: {
           name: simple(:name),
           arguments: sequence(:arguments)
         }) {
      next if ["flagdeco", "flagicon", "flagicon image", "refn", "sfn"].include?(name)
      next arguments.first.to_s if arguments.length == 1 && ["nowrap", "small"].include?(name)

      is_infobox = name.to_s.downcase.start_with?("infobox ")
      s = "{{#{name}"
      separator = is_infobox ? "\n|" : "|"
      s += separator + arguments.join(separator) unless arguments.empty?
      s += "\n" if is_infobox
      s += "}}"
      s
    }
    rule(xml: {
           l: {"tag" => simple(:tag)},
           r: {"tag" => simple(:tag)},
           v: sequence(:v)
         }) { v.join(" ") }
  end

  t.apply(tree)
end
