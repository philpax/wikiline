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
    it_can_parse_and_reformat "[[test|'''lol''']]"
  end

  it 'can parse a br inside a link' do
    it_can_parse_and_reformat '[[Hippias (tyrant)|Hippias (deposed<br/>Athenian tyrant)]]'
  end

  it 'can reformat the Battle of Marathon' do
    infobox = it_can_parse_and_reformat <<-DOC
{{Infobox military conflict
|conflict=Battle of Marathon
|partof=the [[First Persian invasion of Greece]]
|image=Scene of the Battle of Marathon.jpg
|image_size=300px
|caption=Battle of Marathon
|date= August/September ([[Attic calendar|Metageitnion]]), 490 BC
|place=[[Marathon, Greece]]
|result=
Greek victory
* Persian forces conquer the Cycladic islands and establish control over the Aegean sea<ref>{{cite book |last1=Briant |first1=Pierre |title=From Cyrus to Alexander: A History of the Persian Empire |date=2002 |publisher=Eisenbrauns |isbn=9781575061207 |url=https://books.google.com/books?id=lxQ9W6F1oSYC&pg=PA158 |page=158|language=en}}</ref>
* Persian forces driven out of mainland Greece for 10 years<ref name=Dougherty>100 Battles, ''Decisive Battles that Shaped the World'', Dougherty, Martin, J., Parragon, p. 12</ref>
|map_type = Greece
|map_relief = yes
|coordinates = {{Coord|38|07|05|N|23|58|42|E|region:GR_type:event|display=inline,title}}
|map_size = 300
|map_marksize = 7
|map_caption = Location of the Battle of Marathon
|map_label   =
|combatant1=[[Classical Athens|Athens]]<br /> [[Plataea]]
|combatant2={{Flagcountry|Achaemenid Empire}}
|commander1=[[Miltiades]]<br />[[Callimachus (polemarch)|Callimachus]]{{KIA}}<br />[[Aristides|Aristides the Just]]<br />[[Xanthippos|Xanthippus]] ([[Pericles]]' father)<br />[[Themistocles]]<br />Stesilaos{{KIA}}<br />[[Arimnestos]]<ref>{{cite web|url=http://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0160:book=9:chapter=4:section=2|title=Pausanias, Description of Greece, Boeotia, chapter 4, section 2|website=www.perseus.tufts.edu}}</ref>
|commander2=[[Datis]]<br /> [[Artaphernes (son of Artaphernes)|Artaphernes]]<br />[[Hippias (tyrant)|Hippias (deposed<br/>Athenian tyrant)]]
|strength1=9,000–10,000 Athenians,<br />1,000 Plataeans
|strength2=25,000 infantry and 1,000 cavalry (modern estimates)<ref name=Dougherty/> (the latter was not engaged)<br />100,000+ armed oarsmen and sailors (arranged as reserve troops they saw little action, mostly defending the ships)<br />600 [[trireme]]s<br />50+ horse-carriers<br />200+ supply ships
|casualties1=192 Athenians, <br />11 Plataeans ([[Herodotus]]) <br /> 1,000–3,000 dead (modern estimates)<ref name="Krentz, Peter 2010 p. 98">Krentz, Peter, ''The Battle of Marathon'' (Yale Library of Military History), Yale Univ Press, (2010) p. 98</ref>
|casualties2=6,400 dead <br />7 ships destroyed ([[Herodotus]])<br /> 4,000–5,000 dead (modern estimates)<ref name="Krentz, Peter 2010 p. 98"/>
}}
DOC

    expect(infobox).to eq (<<-DOC
{{Infobox military conflict
|conflict=Battle of Marathon
|partof=the  First Persian invasion of Greece
|image=Scene of the Battle of Marathon.jpg
|image_size=300px
|caption=Battle of Marathon
|date=August/September ( Metageitnion ), 490 BC
|place=Marathon, Greece
|result=Greek victory * Persian forces conquer the Cycladic islands and establish control over the Aegean sea  * Persian forces driven out of mainland Greece for 10 years
|map_type=Greece
|map_relief=yes
|coordinates={{Coord|38|07|05|N|23|58|42|E|region:GR_type:event|display=inline,title}}
|map_size=300
|map_marksize=7
|map_caption=Location of the Battle of Marathon
|map_label=
|combatant1=Athens Plataea
|combatant2={{Flagcountry|Achaemenid Empire}}
|commander1=Miltiades Callimachus {{KIA}} Aristides the Just Xanthippus ( Pericles ' father) Themistocles Stesilaos {{KIA}} Arimnestos
|commander2=Datis Artaphernes Hippias (deposedAthenian tyrant)
|strength1=9,000–10,000 Athenians, 1,000 Plataeans
|strength2=25,000 infantry and 1,000 cavalry (modern estimates)
|casualties2=6,400 dead  7 ships destroyed ( Herodotus ) 4,000–5,000 dead (modern estimates)
}}
DOC
    ).strip
  end

  it 'can parse an East Asian infobox' do
    it_can_parse_and_reformat <<-DOC
{{Infobox East Asian
| color = #CCCCFF
| koreanname = South Korean name
| hangul = 한국전쟁
| hanja = 韓國戰爭
| rr = Hanguk Jeonjaeng
| mr = Han'guk Chŏnjaeng
| koreanname2 = North Korean name
| context2 = north
| hangul2 = 조국해방전쟁
| hanja2 = 祖國解放戰爭
| rr2 = Joguk haebang Jeonjaeng
| mr2 = Choguk haebang chǒnjaeng
}}
DOC
  end

  it 'can parse an extraneous div closing tag' do
    it_can_parse_and_reformat '<div>lol</div></div>'
  end

  it 'can parse the XML from the Munich massacre' do
    it_can_parse_and_reformat <<-DOC
<div style="width:250px;float:none;clear:none;"><div style="position:relative;padding:0;width:250px;">
[[File:Germany, Federal Republic of location map January 1957 - October 1990.svg|250px|Map of West Germany (the Federal Republic of Germany between 1949 and 1990)]]<div style="position:absolute;z-index:2;top:87.8%;left:60.3%;height:0; width:0;margin:0;padding:0;"><div style="position:relative;text-align:center;left:-3px;top:-3px;width:6px;font-size:6px;">[[File:Red pog.svg|7px|Locator dot]]</div><div style="font-size:90%;line-height:110%;position:relative;top:-1.5em;width:6.0em;top:-0.65em;left:-3.0em;text-align:center;"><span style="padding:1px;">'''Munich'''</span></div></div></div></div>
DOC
  end

  it 'can parse the Munich massacre' do
    it_can_parse_and_reformat <<-DOC
{{Infobox terrorist attack
| title = Munich massacre
| image = Ap munich905 t.jpg
| image_upright = 1.15
| caption = {{longitem|One of the most reproduced photos taken during the siege shows a kidnapper on the balcony attached to [[Olympic Village, Munich|Munich Olympic village]] Building 31, where members of the [[Israel at the 1972 Summer Olympics|Israeli Olympic team and delegation]] were quartered.<ref>{{cite news |title=Messages from 'Munich'|last=Breznican|first=Anthony|date=22 December 2005|work=USAToday|publisher=Gannett Co.|url=https://www.usatoday.com/life/movies/news/2005-12-21-munich_x.htm|accessdate=17 April 2009}}</ref><ref>{{cite news|url=http://www.time.com/time/arts/article/0,8599,54669,00.html| title=Revisiting the Olympics' Darkest Day|work=Time|date=12 September 2000|first=Tony|last=Karon|archiveurl=https://web.archive.org/web/20071001002614/http://www.time.com/time/arts/article/0,8599,54669,00.html|archivedate=1 October 2007|accessdate=13 May 2010}}</ref>}}
| map = <div style="width:250px;float:none;clear:none;"><div style="position:relative;padding:0;width:250px;">
[[File:Germany, Federal Republic of location map January 1957 - October 1990.svg|250px|Map of West Germany (the Federal Republic of Germany between 1949 and 1990)]]<div style="position:absolute;z-index:2;top:87.8%;left:60.3%;height:0; width:0;margin:0;padding:0;"><div style="position:relative;text-align:center;left:-3px;top:-3px;width:6px;font-size:6px;">[[File:Red pog.svg|7px|Locator dot]]</div><div style="font-size:90%;line-height:110%;position:relative;top:-1.5em;width:6.0em;top:-0.65em;left:-3.0em;text-align:center;"><span style="padding:1px;">'''Munich'''</span></div></div></div></div>
| coordinates = {{coord|48|10|47|N|11|32|57|E|region:DE-BY_scale:50000_type:event|display=inline,title}}
| location = [[Munich]], [[West Germany]]
| target = [[Israel at the Olympics|Israeli Olympic team]]
| date = 5–6 September 1972
| time = 4:31&nbsp;am&nbsp;– 12:04&nbsp;am
| timezone = [[UTC]]+1
| type = {{unbulleted list|[[Hostage-taking]]|[[Mass shooting]]|[[Massacre]]}}
| fatalities = 17 total (including perpetrators)
*6 Israeli coaches
*5 Israeli athletes
*5 Black September members
*1 West German police officer
| perps = [[Black September Organization|Black September]]
| motive = [[Israeli–Palestinian conflict]]
}}
DOC
  end

  it 'can parse the Battle of Gettysburg' do
    it_can_parse_and_reformat <<-DOC
{{Infobox military conflict
 |conflict   = Battle of Gettysburg
 |partof     = the [[Eastern Theater of the American Civil War|Eastern Theater]] of the [[American Civil War]]
 |image      = [[File:Thure de Thulstrup - L. Prang and Co. - Battle of Gettysburg - Restoration by Adam Cuerden.jpg|border|300px]]<!-- EDITORS NOTE: Please do not change the image without prior consensus, see [[Talk:Pickett's Charge]]. Thank you. -->
 |caption    = The '' '''Battle of Gettysburg''' '' by [[Thure de Thulstrup]]<!-- EDITORS NOTE: Please do not change this caption as it currently conforms to TemplateData for Infobox military conflict. Thank you. -->
 |date       = July 1–3, 1863
 |place      = [[Gettysburg, Pennsylvania]]
 |coordinates= {{Coord|39.811|N|77.225|W|type:event_region:US_scale:30000|display=inline,title}}<!-- NPS visitor center location-->
 |no-location-property=yes
 |result     = [[Union (American Civil War)|Union]] victory<ref>Coddington, p. 573. See the [[#decisive|discussion]] regarding historians' judgment on whether Gettysburg should be considered a [[decisive victory]].</ref>
 |combatant1 = {{flagcountry|USA|1861}}
 |combatant2 = {{flagcountry|CSA|1863}}
 |commander1 = [[George Meade|George G. Meade]]
 |commander2 = [[Robert E. Lee]]
 |units1     = [[Army of the Potomac]]<ref>''Official Records'', Series I, Volume XXVII, Part 1, [http://ebooks.library.cornell.edu/cgi/t/text/pageviewer-idx?c=moawar&cc=moawar&idno=waro0043&node=waro0043%3A2&view=image&seq=175&size=100 pages 155–168]</ref>
 |units2     = [[Army of Northern Virginia]]<ref>''Official Records'', Series I, Volume XXVII, Part 2, [http://ebooks.library.cornell.edu/cgi/t/text/pageviewer-idx?c=moawar&cc=moawar&idno=waro0044&node=waro0044%3A2&view=image&seq=285&size=100 pages 283–291]</ref>
 |strength1  = 104,256 ("present for duty")<ref>''Official Records'', Series I, Volume XXVII, Part 1, [http://ebooks.library.cornell.edu/cgi/t/text/pageviewer-idx?c=moawar&cc=moawar&idno=waro0043&q1=return+of+casualties&view=image&seq=193&size=100 page 151]</ref><ref name=BM125>Busey and Martin, p. 125: "Engaged strength" at the battle was 93,921.</ref>
 |strength2  = 71,000–75,000 (estimated)<ref name=BM260>Busey and Martin, p. 260, state that "engaged strength" at the battle was 71,699; McPherson, p. 648, lists the strength at the start of the campaign as 75,000.</ref>
|casualties1 = '''23,049''' total<div style="line-height:1.2em;">(3,155 killed;<br />14,529 wounded;<br />5,365 captured/missing)</div><ref>''Official Records'', Series I, Volume XXVII, Part 1, [http://ebooks.library.cornell.edu/cgi/t/text/pageviewer-idx?c=moawar&cc=moawar&idno=waro0043&q1=return+of+casualties&view=image&seq=207&size=100 page 187]</ref><ref name=Ucasualties>Busey and Martin, p. 125.</ref>
|casualties2 = '''23,000–28,000''' (estimated)<ref name=Ccasualties>Busey and Martin, p. 260, cite '''23,231''' total (4,708 killed;12,693 wounded;5,830 captured/missing).<br />
See the section on [[#Casualties|casualties]] for a discussion of alternative Confederate casualty estimates, which have been cited as high as '''28,000'''.</ref><ref>''Official Records'', Series I, Volume XXVII, Part 2, [http://ebooks.library.cornell.edu/cgi/t/text/pageviewer-idx?c=moawar;cc=moawar;q1=return%20of%20casualties;rgn=full%20text;idno=waro0044;didno=waro0044;view=image;seq=0340 pages 338–346]</ref></div>
| campaignbox= {{Campaignbox Gettysburg Campaign}}
}}
DOC
  end
end
