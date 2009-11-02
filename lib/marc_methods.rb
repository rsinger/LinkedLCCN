def model_sound(marc, resource)
  resource.relate("[rdf:type]", "[mo:Recording]")
  upcs = marc.find_all {|f| f.tag == "024"}
  upcs.each do | upc |
    next unless upc.indicator1 == "1"
    resource.assert("[mo:barcode]", upc['a'])
    mbrainz = dbtune_lookup(upc['a'])
    if mbrainz
      resource.relate("[owl:sameAs]", mbrainz[:release]) if mbrainz[:release]
      if mbrainz[:record] && mbrainz[:record].foaf["maker"]
        resource.assert("[dcterms:creator]", mbrainz[:record].foaf["maker"])
        if mbrainz[:record].mo["track"]
          [*mbrainz[:record].mo["track"]].each do | track |            
            resource.assert("[mo:track]", track)
          end
        end
        if mbrainz[:record].owl['sameAs']
          [*mbrainz[:record].owl['sameAs']].each do | sames |
            if sames.uri =~ /^http:\/\/dbpedia\.org\//
              resource.assert("[rdfs:seeAlso]", sames)
            end
          end
        end
      end
    end
  end
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
        collection = periodical.describe
      
        if collection[periodical.uri].owl && collection[periodical.uri].owl['sameAs']
          [*collection[periodical.uri].owl['sameAs']].each do | same_as |
            resource.assert("[owl:sameAs]", same_as)
          end
        end
      rescue RuntimeError
      end
    end
  end
end

def model_map(marc, resource)
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
  end
  
  if marc['022'] && marc['022']['a']
    resource.assert("[bibo:issn]", marc['022']['a'].strip_trailing_punct)
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
      subj = Resource.new("http://lccn.heroku.com/subjects/#{CGI.escape(literal)}")
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
      resource.relate("[dcterms:creator]", viaf)
    end
  end
  auths = marc.find_all {|f| f.tag == '700'}
  auths.each do | auth |
    if viaf = viaf_lookup(auth)
      resource.relate("[dcterms:creator]", viaf)
    end
  end    
end

def to_rdf(marc)
  id = marc['010'].value.strip
  resource = Resource.new("http://lccn.heroku.com/#{id}#i")
  resource.relate("[foaf:isPrimaryTopicOf]", "http://lccn.loc.gov/#{id}")  
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
