require 'ken'
def model_sound(marc, resource)
  resource.relate("[rdf:type]", "[mo:Recording]")
  upcs = marc.find_all {|f| f.tag == "024"}
  mbrainz_params = {:title=>marc['245']['a']}
  mbrainz_params[:artist] = case
  when marc['100'] then marc['100']['a']
  when marc['110'] then marc['110']['a']
  when marc['111'] then marc['111']['a']
  when marc['700'] then marc['700']['a']
  when marc['710'] then marc['710']['a']
  end
  mbrainz = {}
  unless upcs.empty?
    upcs.each do | upc |
      next unless upc.indicator1 == "1"
      resource.assert("[mo:barcode]", upc['a'])
      mbrainz_params[:barcode] ||=[]
      mbrainz_params[:barcode] << upc['a']
    end
  end
  cat_nums = marc.find_all {|f| f.tag == "028"}
  cat_nums.each do | cat_num |
    if cat_num['a']
      resource.assert("[mo:catalogue_number]", cat_num['a'])
      mbrainz_params[:catno] ||=[]
      mbrainz_params[:catno] << cat_num['a']
    end
    if cat_num['b']
      mbrainz_params[:label] ||=[]
      mbrainz_params[:label] << cat_num['b']
    end
  end

  if mbrainz = musicbrainz_lookup(mbrainz_params)
    if mbrainz[:release]
      mbrainz[:release].each do | r |
        resource.relate("[owl:sameAs]", r)
      end
    end
    if mbrainz[:record]
      mbrainz[:record].each do | r |
        resource.relate("[dcterms:isVersionOf]", r)
      end
    end
    if mbrainz[:tracks]
      mbrainz[:tracks].each do | t |
        resource.relate("[mo:track]", t)
      end
    end
    if mbrainz[:labels]
      mbrainz[:labels].each do | l |
        resource.relate("[mo:label]", l)
      end
    end

  end
  #unless mbrainz.nil? or mbrainz.empty?
  #  if mbrainz[:release]
  #    [*mbrainz[:release]].each do | release |
  #      resource.relate("[owl:sameAs]", release)
  #    end
  #  end
  #  if mbrainz[:record]
  #    [*mbrainz[:record]].each do | record |
  #      resource.assert("[dcterms:creator]", record.foaf["maker"]) if record.foaf["maker"]
  #      if record.mo["track"]
  #        [*record.mo["track"]].each do | track |
  #          resource.assert("[mo:track]", track)
  #        end
  #      end
  #      if record.owl['sameAs']
  #        [*record.owl['sameAs']].each do | sames |
  #          if sames.uri =~ /^http:\/\/dbpedia\.org\//
  #            resource.assert("[rdfs:seeAlso]", sames)
  #          end
  ##        end
  #      end
  #    end
  #  end
  #end
  
end

def model_book(marc, resource)
  if marc.is_conference?
    resource.relate("[rdf:type]","[bibo:Proceedings]")
  elsif marc.is_manuscript?
    resource.relate("[rdf:type]","[bibo:Manuscript]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("m")
    resource.relate("[rdf:type]","[bibo:Thesis]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("u")
    resource.relate("[rdf:type]","[bibo:Standard]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("j")
    resource.relate("[rdf:type]","[bibo:Patent]")    
  elsif marc.nature_of_contents && marc.nature_of_contents.index("t")
    resource.relate("[rdf:type]","[bibo:Report]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("l")
    resource.relate("[rdf:type]","[bibo:Legislation]")
  elsif marc.nature_of_contents && marc.nature_of_contents.index("v")
    resource.relate("[rdf:type]","[bibo:LegalCaseDocument]")
  elsif marc.nature_of_contents && !(marc.nature_of_contents & ["d", "e", "r"]).empty?
    resource.relate("[rdf:type]","[bibo:ReferenceSource]")
  else
    resource.relate("[rdf:type]", "[bibo:Book]")
  end
  if marc.nature_of_contents
    marc.nature_of_contents(true).each do | genre |        
      resource.assert("[dcterms:type]", genre)
    end
  end
  if ol = openlibrary_lookup(marc['010'].value.strip)
    resource.relate("[owl:sameAs]", "http://openlibrary.org#{ol.first['key']}")
  end
  freebase = case
  when marc['100'] then freebase_book_lookup(marc['245']['a'].strip_trailing_punct, marc['100'])
  when marc['111'] then freebase_book_lookup(marc['245']['a'].strip_trailing_punct, marc['110'])
  else nil
  end
  if freebase
    resource.relate("[dcterms:isVersionOf]", freebase)
  end
      
end

def model_serial(marc, resource)
  if marc.nature_of_contents
    marc.nature_of_contents(true).each do | genre |        
      resource.assert("[dcterms:type]", genre)
    end
  end
  type = marc.serial_type(true)
  if type == 'Newspaper'
    resource.relate("[rdf:type]","[bibo:Newspaper]")
  elsif type == 'Website'
    resource.relate("[rdf:type]","[bibo:Website]") 
  elsif type == 'Periodical'    
    if marc['245'].to_s =~ /\bjournal\b/i
      resource.relate("[rdf:type]","[bibo:Journal]")
    elsif marc['245'].to_s =~ /\bmagazine\b/i
      resource.relate("[rdf:type]","[bibo:Magazine]")
    else
     resource.relate("[rdf:type]","[bibo:Periodical]")
    end
  end
  if marc['022']
    issn = marc['022']['a'].gsub(/[^0-9{4}\-?0-9{3}0-9Xx]/,"") if marc['022']['a']
    unless issn.empty?
      periodical = Resource.new("http://periodicals.dataincubator.org/issn/#{issn}") 
      begin
        periodical.describe
        if periodical.owl && periodical.owl['sameAs']
          [*periodical.owl['sameAs']].each do | same_as |
            resource.assert("[owl:sameAs]", same_as)
          end
        end
      rescue RuntimeError
      end
    end
    if freebase = freebase_journal_lookup(marc['245']['a'].strip_trailing_punct, issn)
      resource.assert("[owl:sameAs]", freebase)
    end
    if dbpedia = dbpedia_journal_lookup(marc['245']['a'].strip_trailing_punct, issn)
      resource.assert("[owl:sameAs]", dbpedia)
    end    
  end
end

def model_map(marc, resource)
  resource.relate("[rdf:type]", "[bibo:Map]")
  cart = marc.find_all {|f| f.tag == "034"}
  cart.each do | c |
    if c['d'] and c['e'] and c['f'] and c['g']
      west = coordinate_to_decimal(c['d'])
      east = coordinate_to_decimal(c['e'])      
      north = coordinate_to_decimal(c['f'])
      south = coordinate_to_decimal(c['g'])
      resource.assert("http://www.georss.org/georss#box", "#{south} #{west} #{north} #{east}")
    end
  end
end

def coordinate_to_decimal(coordinate)
  return coordinate if coordinate =~ /\-?[0-9]{3}\.[0-9]*/
  decimal = nil
  if coordinate !~ /\./
    decimal = coordinate.sub(/^[SW]/,"-").sub(/^[NE]/,"")
    decimal.sub!(/([0-9]{3})/,'\1.')
  end
  if decimal && decimal =~ /\.[0-9]{4}/
    minsec = decimal.match(/\.([0-9]{2})([0-9]{2})/)
    minute = (minsec[1].to_i/60)
    second = (minsec[2].to_i/3600)
    (degree, mmss) = decimal.split(/\./)
    decimal = "#{degree}.#{minute}#{second}"
  end
  return decimal
end

def model_visual(marc, resource)
  type = marc.material_type(true)
  if (type == "Videorecording" or type == "Motion picture") or (marc['245'] && marc['245']['h'] && marc['245']['h'] =~ /videorecording/)
    resource.relate("[rdf:type]","[bibo:Film]")
    if linkedmdb = linkedmdb_lookup(marc['245']['a'].strip_trailing_punct)
      resource.relate("[dcterms:isVersionOf]", linkedmdb)
    elsif dbpedia = dbpedia_film_lookup(marc['245']['a'].strip_trailing_punct)
      resource.relate("[dcterms:isVersionOf]", dbpedia)
    end
  elsif type
    resource.assert("[dct:type]", type)
  end  
end

def model_generic(marc, resource)
end

def marc_common(resource, marc)
  if marc['245']
    if marc['245']['a']
      title = marc['245']['a'].strip_trailing_punct
      resource.assert("[rda:titleProper]", marc['245']['a'].strip_trailing_punct)
    end
    if marc['245']['b']
      title << " "+marc['245']['b'].strip_trailing_punct
      resource.assert("[rda:otherTitleInformation]", marc['245']['b'].strip_trailing_punct)
    end
    if marc['245']['c']
      resource.assert("[rda:statementOfResponsibility]", marc['245']['c'].strip_trailing_punct)
    end
  end
  if marc['245']['n']
    resource.assert("[bibo:number]", marc['245']['n'])
  end
  resource.assert("[dcterms:title]", title)
  if marc['210']
    resource.assert("[bibo:shortTitle]", marc['210']['a'].strip_trailing_punct)
  end
  if marc['020'] && marc['020']['a']
    isbn = ISBN_Tools.cleanup(marc['020']['a'].strip_trailing_punct)
    if ISBN_Tools.is_valid?(isbn)
      if isbn.length == 10
        resource.assert("[bibo:isbn10]",isbn)
        resource.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{isbn}#book")
        resource.assert("[bibo:isbn13]", ISBN_Tools.isbn10_to_isbn13(isbn))
      else
        resource.assert("[bibo:isbn13]",isbn)
        resource.assert("[bibo:isbn10]", ISBN_Tools.isbn13_to_isbn10(isbn))          
        resource.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{ISBN_Tools.isbn13_to_isbn10(isbn)}#book")  
        isbn = ISBN_Tools.isbn13_to_isbn10(isbn) 
      end
      library_thing = Resource.new("http://dilettantes.code4lib.org/LODThing/isbns/#{isbn}#book") 
      begin
        collection = library_thing.describe
        resource.relate("[owl:sameAs]", library_thing)
      rescue RuntimeError
      end      
    end   
    resource.relate("[dcterms:isVersionOf]", "http://xisbn.worldcat.org/webservices/xid/isbn/#{isbn}?method=getMetadata&format=xml&fl=*")   
  end
  
  if marc['022'] && marc['022']['a']
    resource.assert("[bibo:issn]", marc['022']['a'].strip_trailing_punct)
    resource.relate("[dcterms:isVersionOf]", "http://xissn.worldcat.org/webservices/xid/issn/#{marc['022']['a'].strip_trailing_punct}?method=getForms&format=xml")
  end  
  
  subjects = marc.find_all {|field| field.tag =~ /^6../}
  
  subjects.each do | subject |
    literal = subject_to_string(subject)
    #resource.assert("[dc:subject]", literal)
    authority = nil
    if !["653","690","691","696","697", "698", "699"].index(subject.tag) && subject.indicator2 =~ /^(0|1)$/      
      
      authority = get_lcsh(literal)
      if authority
        resource.relate("[dcterms:subject]", authority)
      end
    end
    unless authority
      subj = Resource.new("http://purl.org/NET/lccn/subjects/#{CGI.escape(literal)}")
      subj.relate("[rdf:type]", "[skos:Concept]")
      subj.assert("[skos:prefLabel]", literal)
      resource.relate("[dcterms:subject]", subj)
    end  
  end
  
  if marc['250'] && marc['250']['a']
    resource.assert("[bibo:edition]", marc['250']['a'])
  end
  if marc['246'] && marc['246']['a']
    resource.assert("[rda:parallelTitleProper]", marc['246']['a'].strip_trailing_punct)
  end
  if marc['767'] && marc['767']['t']
    resource.assert("[rda:parallelTitleProper]", marc['767']['t'].strip_trailing_punct)
  end  
  
  if marc['100']
    if viaf = viaf_lookup(marc['100'])
      loc_creator_search(viaf)
      relator_to_rdf(marc['100']).each do | relator |
        resource.relate(relator, viaf)
      end
    end
  end
  auths = marc.find_all {|f| f.tag == '700'}
  auths.each do | auth |
    if viaf = viaf_lookup(auth)
      loc_creator_search(viaf)
      relator_to_rdf(auth).each do | relator |
        resource.relate(relator, viaf)
      end 
    end
  end   
  
  links = marc.find_all{|f| f.tag == '856'} 
  links.each do | link |
    if link.indicator2 == "1"
      resource.assert("[bibo:uri]", link['u']) if link['u']
    end
  end
  marc.languages.each do | lang |
    next unless lang
    resource.relate("[dcterms:language]", "http://purl.org/NET/marccodes/languages/#{lang.three_code}#lang")
  end
  
  if country = marc.publication_country
    resource.relate("[rda:placeOfPublication]", "http://purl.org/NET/marccodes/countries/#{country}#location")
  end
  
  gacs = marc.find_all{|f| f.tag == '043'}
  gacs.each do | gac |
    l = gac.find_all{|f| f.code == 'a'}
    l.each do | subfield |
      resource.relate("[foaf:topic]","http://purl.org/NET/marccodes/gacs/#{subfield.value.sub(/-*$/,"")}#location")
    end
  end
end

def relator_to_rdf(field)
  relators = []
  subfields = ['4', 'e']
  subfields.each do | sub |
    fields = field.find_all {|s| s.code == sub}
    fields.each do |subfield|
      if rel = RELATORS[:codes][subfield.value]
        if rel['use']
          [*rel['use']].each do | use |
            relators << use['relationship']
          end
        else
          relators << rel['relationship']
        end
      else        
        @missing_relators << subfield.value
      end
    end
    break unless relators.empty?
  end
  if relators.empty?
    if ['100','110','111'].index(field.tag)
      relators << "[dcterms:creator]"
    else
      relators << "[dcterms:contributor]"
    end
  end
  relators
end

def to_rdf(marc)
  id = marc['010'].value.strip.gsub(/\s/,'')
  resource = Resource.new("http://purl.org/NET/lccn/#{CGI.escape(id)}#i")
  resource.relate("[foaf:isPrimaryTopicOf]", "http://lccn.loc.gov/#{CGI.escape(id)}") 
  resource.assert("[bibo:lccn]", id)
  case marc.class.to_s
  when "MARC::SoundRecord" then model_sound(marc, resource)
  when "MARC::BookRecord" then model_book(marc, resource)
  when "MARC::SerialRecord" then model_serial(marc, resource)
  when "MARC::MapRecord" then model_map(marc, resource)
  when "MARC::VisualRecord" then model_visual(marc, resource)
  else model_generic(marc, resource)
  end
  marc_common(resource, marc)
  resource
end

def subject_to_string(subject)
  literal = ''
  subject.subfields.each do | subfield |
    if !literal.empty?
      if ["v","x","y","z"].index(subfield.code)
        literal << '--'
      elsif ["2","5"].index(subfield.code)
        next
      else
        literal << ' ' if subfield.value =~ /^[\w\d]/
      end
    end
    literal << subfield.value
  end
  literal.strip_trailing_punct  
end
