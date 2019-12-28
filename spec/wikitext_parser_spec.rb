# coding: utf-8
require './analysis/wikitext_parser'
require 'parslet/rig/rspec'
require 'json'

RSpec.describe WikitextParser do
  def it_can_parse(doc, parser = WikitextParser.new)
    tree = parser.parse(doc)
    expect(tree).to be_a(Hash)

    tree
  end

  def it_can_parse_and_reformat(doc, parser = WikitextParser.new)
    tree = it_can_parse(doc, parser)

    simplified_doc = text_print(tree)
    expect(simplified_doc).to be_a(String)

    simplified_doc
  end

  it 'can parse links' do
    it_can_parse_and_reformat '[[British Bull Dog revolver|Bulldog Revolver]]'
  end

  it 'can parse a link inside a macro argument' do
    it_can_parse_and_reformat '| type = [[Assassination]]', WikitextParser.new.macro_argument
  end

  it 'can parse a macro argument with plain text' do
    it_can_parse_and_reformat '|Assassination of James A. Garfield', WikitextParser.new.macro_argument
  end

  it 'can parse a macro argument with a macro' do
    it_can_parse_and_reformat '| title = {{nowrap|Assassination of James A. Garfield}}', WikitextParser.new.macro_argument
  end

  it 'can parse a macro argument with a complex macro' do
    it_can_parse_and_reformat ' | coordinates = {{Coord|38|53|31|N|77|01|13|W|region:US-DC_type:event|display=inline,title}}', WikitextParser.new.macro_argument
  end

  it 'can parse a small' do
    it_can_parse '<small>lol</small>', WikitextParser.new.xml_tag
  end

  it 'can parse a ref' do
    it_can_parse '<ref>lol</ref>', WikitextParser.new.xml_tag
    it_can_parse '<ref somemeta="garbage">lol</ref>', WikitextParser.new.xml_tag
  end

  it 'can parse a line break' do
    it_can_parse '<br/>', WikitextParser.new.xml_tag
    it_can_parse '<br />', WikitextParser.new.xml_tag
  end

  it 'can parse a comment' do
    it_can_parse '<!--lol-->', WikitextParser.new.comment
  end

  it 'can parse the Garfield location' do
    it_can_parse_and_reformat ' | location = [[Baltimore and Potomac Railroad Station]]<br />[[Washington, D.C.]], U.S.', WikitextParser.new.macro_argument
  end

  it 'can parse the Garfield caption' do
    it_can_parse_and_reformat %q(| caption = President Garfield with [[James G. Blaine]] after being shot by [[Charles J. Guiteau]]<ref>Cheney, Lynne Vincent. [http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml "Mrs. Frank Leslie's Illustrated Newspaper"] {{webarchive |url=https://web.archive.org/web/20070929090303/http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml |date=September 29, 2007 }}. American Heritage Magazine. October 1975. Volume 26, Issue 6. ''URL retrieved on January 24, 2007.''</ref>), WikitextParser.new.macro_argument
  end

  it 'can parse the full Garfield infobox' do
    it_can_parse_and_reformat <<-DOC
{{Infobox civilian attack
| title = {{nowrap|Assassination of James A. Garfield}}
| image = Garfield assassination engraving cropped.jpg
| caption = President Garfield with [[James G. Blaine]] after being shot by [[Charles J. Guiteau]]<ref>Cheney, Lynne Vincent. [http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml "Mrs. Frank Leslie's Illustrated Newspaper"] {{webarchive |url=https://web.archive.org/web/20070929090303/http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml |date=September 29, 2007 }}. American Heritage Magazine. October 1975. Volume 26, Issue 6. ''URL retrieved on January 24, 2007.''</ref><ref>[http://lcweb2.loc.gov/cgi-bin/query/D?presp:4:./temp/~ammem_d2P8:: "The attack on the President's life"]. Library of Congress. ''URL retrieved on January 24, 2007.''</ref>
| location = [[Baltimore and Potomac Railroad Station]]<br />[[Washington, D.C.]], U.S.
| coordinates = {{Coord|38|53|31|N|77|01|13|W|region:US-DC_type:event|display=inline,title}}
| target = [[James A. Garfield]]
| date = July 2, 1881, {{age|1881
|07|02}} years ago
| time = 9:30&nbsp;am
| timezone = [[Local mean time]]
| type = [[Assassination]]
| weapons = [[British Bull Dog revolver|Bulldog Revolver]]
| fatalities = 1 (Garfield; died on September 19, 1881 as a result of infection)
| injuries = None
| perp = [[Charles J. Guiteau]]
| motive = Retribution for perceived failure to reward campaign support
}}
DOC
  end

  it 'can parse a macro argument with a comment followed by a macro' do
    doc = <<-DOC
|result= <!--DO NOT ALTER WITHOUT CONSENSUS-->
{{Collapsible list}}
DOC
    it_can_parse_and_reformat doc, WikitextParser.new.macro_argument
  end

  it 'can parse a French refn' do
    it_can_parse '{{refn|[[Anglo-French War (1778–83)|(from 1778)]]}}', WikitextParser.new.macro
    it_can_parse '{{refn|The term "French Empire" colloquially refers to the [[First French Empire|empire under Napoleon]], but it is used here for brevity to refer to France proper and to the colonial empire that the [[Kingdom of France]] ruled}}', WikitextParser.new.macro
  end

  it 'can parse the American Revolutionary War infobox' do
    infobox = File.read 'spec/support/arw-infobox.txt'
    it_can_parse_and_reformat infobox
  end

  it 'can parse an empty macro argument' do
    it_can_parse '{{lol|}}', WikitextParser.new.macro
    it_can_parse '{{lol|xyz=}}', WikitextParser.new.macro
  end

  it 'can meaningfully parse an image tag' do
    it_can_parse '[[File:Why This.jpg]]'
    it_can_parse '[[File:Why This.jpg|thumb]]'
    it_can_parse '[[File:Why This.jpg|thumb|center|page=Lol|Some Image]]'
    it_can_parse '[[File:Wappen Brandenburg-Ansbach.svg|19px|link=]] '
  end

  it 'can parse a small tag in context' do
    it_can_parse '<small>lol</small>'
    it_can_parse_and_reformat '{{template|arg=<small>lol</small>}}'
    it_can_parse_and_reformat '{{template|strength2=<small><br /></small>}}'
    it_can_parse_and_reformat '{{template|strength2=<br /><small>lol</small>}}'
    it_can_parse_and_reformat <<-DOC
{{template|strength2=
<small>
  '''[[British Army during the American Revolutionary War|Army]]:'''
  <br />
  171,000 sailors
  <ref name="Mackesy 1964 pp. 6, 176">
    Mackesy (1964), pp. 6, 176 (British seamen).
  </ref>
</small>
}}
DOC
  end

  it 'can parse a bold inside a link' do
    parser = WikitextParser.new
    expect(parser).to parse "[[test|'''lol''']]"
  end
end
