# coding: utf-8
require './analysis/wikitext_parser'
require 'parslet/rig/rspec'

RSpec.describe WikitextParser do
  it 'can parse links' do
    parser = WikitextParser.new
    expect(parser).to parse '[[British Bull Dog revolver|Bulldog Revolver]]'
  end

  it 'can parse a link inside a macro argument' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse '| type = [[Assassination]]'
  end

  it 'can parse a macro argument with plain text' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse '|Assassination of James A. Garfield'
  end

  it 'can parse a macro argument with a macro' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse '| title = {{nowrap|Assassination of James A. Garfield}}'
  end

  it 'can parse a macro argument with a complex macro' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse ' | coordinates = {{Coord|38|53|31|N|77|01|13|W|region:US-DC_type:event|display=inline,title}}'
  end

  it 'can parse a small' do
    parser = WikitextParser.new
    expect(parser.xml_tag).to parse '<small>lol</small>'
  end

  it 'can parse a ref' do
    parser = WikitextParser.new
    expect(parser.xml_tag).to parse '<ref>lol</ref>'
    expect(parser.xml_tag).to parse '<ref somemeta="garbage">lol</ref>'
  end

  it 'can parse a line break' do
    parser = WikitextParser.new
    expect(parser.xml_tag).to parse '<br/>'
    expect(parser.xml_tag).to parse '<br />'
  end

  it 'can parse a comment' do
    parser = WikitextParser.new
    expect(parser.comment).to parse '<!--lol-->'
  end

  it 'can parse the Garfield location' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse ' | location = [[Baltimore and Potomac Railroad Station]]<br />[[Washington, D.C.]], U.S.'
  end

  it 'can parse the Garfield caption' do
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse %q(| caption = President Garfield with [[James G. Blaine]] after being shot by [[Charles J. Guiteau]]<ref>Cheney, Lynne Vincent. [http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml "Mrs. Frank Leslie's Illustrated Newspaper"] {{webarchive |url=https://web.archive.org/web/20070929090303/http://www.americanheritage.com/articles/magazine/ah/1975/6/1975_6_42.shtml |date=September 29, 2007 }}. American Heritage Magazine. October 1975. Volume 26, Issue 6. ''URL retrieved on January 24, 2007.''</ref>)
  end

  it 'can parse the full Garfield infobox' do
    parser = WikitextParser.new
    expect(parser).to parse <<-DOC
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
    parser = WikitextParser.new
    expect(parser.macro_argument).to parse <<-DOC
|result= <!--DO NOT ALTER WITHOUT CONSENSUS-->
{{Collapsible list}}
DOC
  end

  it 'can parse a French refn' do
    parser = WikitextParser.new
    expect(parser.macro).to parse '{{refn|[[Anglo-French War (1778–83)|(from 1778)]]}}'
    expect(parser.macro).to parse '{{refn|The term "French Empire" colloquially refers to the [[First French Empire|empire under Napoleon]], but it is used here for brevity to refer to France proper and to the colonial empire that the [[Kingdom of France]] ruled}}'
  end

  it 'can parse the American Revolutionary War infobox' do
    parser = WikitextParser.new
    infobox = File.read 'spec/support/arw-infobox.txt'
    expect(parser).to parse infobox
  end

  it 'can parse an empty macro argument' do
    parser = WikitextParser.new
    expect(parser.macro).to parse '{{lol|}}'
    expect(parser.macro).to parse '{{lol|xyz=}}'
  end

  it 'can meaningfully parse an image tag' do
    parser = WikitextParser.new
    expect(parser).to parse '[[File:Why This.jpg]]'
    expect(parser).to parse '[[File:Why This.jpg|thumb]]'
    expect(parser).to parse '[[File:Why This.jpg|thumb|center|page=Lol|Some Image]]'
    expect(parser).to parse '[[File:Wappen Brandenburg-Ansbach.svg|19px|link=]] '
  end

  it 'can parse a small tag in context' do
    parser = WikitextParser.new
    expect(parser).to parse '<small>lol</small>'
    expect(parser.parse('<small>lol</small>')).to eq({:xml => {l: {"tag"=>"small"}, v: [{:text=>"lol"}], r: {"tag"=>"small"}}})
    expect(parser).to parse '{{template|arg=<small>lol</small>}}'
    expect(parser).to parse '{{template|strength2=<small><br /></small>}}'
    expect(parser).to parse '{{template|strength2=<br /><small>lol</small>}}'
    expect(parser).to parse <<-DOC
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
