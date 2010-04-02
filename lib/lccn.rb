class LinkedLCCN::LCCN
  attr_reader :lccn, :cached_rdf
  attr_accessor :marc, :graph, :viaf
  def initialize(lccn)
    @lccn = lccn
    @viaf = []
  end
  
  def get_marc
    uri = URI.parse "http://lccn.loc.gov/#{@lccn.gsub(/\s/,"")}/marcxml"
    req = Net::HTTP::Get.new(uri.path)
    res = Net::HTTP.start(uri.host, uri.port) {|http|
      http.request(req)
    }
    return nil unless res.code == "200"
    record = nil
    marcxml = res.body
    marc = MARC::XMLReader.new(StringIO.new(marcxml))
    marc.each {|rec| record = MARC::Record.new_from_marc(rec.to_marc)}
    @marc = record
  end
  
  def cache_rdf
    @cached_rdf = @graph.to_xml(3)
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
          RELATORS[:missing] << subfield.value
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
  
  def basic_rdf
    lccn = @marc['010']['a'].strip
    @graph = RDFObject::Resource.new("http://purl.org/NET/lccn/#{CGI.escape(@lccn)}#i")
    @graph.relate("[foaf:isPrimaryTopicOf]", "http://lccn.loc.gov/#{CGI.escape(@lccn)}") 
    @graph.assert("[bibo:lccn]", lccn)
    marc_common
  end  
  
  def advanced_rdf
    @viaf.each do | viaf |
      if viaf[:type] == :creator
        LinkedLCCN::LibraryOfCongress.creator_search(viaf[:resource])
      end
    end
    case @marc.class.to_s
    when "MARC::SoundRecord" then self.extend(LinkedLCCN::SoundResource)
    when "MARC::BookRecord" then self.extend(LinkedLCCN::BookResource)
    when "MARC::SerialRecord" then self.extend(LinkedLCCN::SerialResource)
    when "MARC::MapRecord" then self.extend(LinkedLCCN::MapResource)
    when "MARC::VisualRecord" then self.extend(LinkedLCCN::VisualResource)
    else self.extend(LinkedLCCN::GenericResource)
    end
    self.model_resource(@marc, @graph)
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
  
  def marc_common
    if @marc['245']
      if @marc['245']['a']
        title = @marc['245']['a'].strip_trailing_punct
        @graph.assert("[rda:titleProper]", @marc['245']['a'].strip_trailing_punct)
      end
      if @marc['245']['b']
        title << " "+@marc['245']['b'].strip_trailing_punct
        @graph.assert("[rda:otherTitleInformation]", @marc['245']['b'].strip_trailing_punct)
      end
      if @marc['245']['c']
        @graph.assert("[rda:statementOfResponsibility]", @marc['245']['c'].strip_trailing_punct)
      end
    end
    if @marc['245']['n']
      @graph.assert("[bibo:number]", @marc['245']['n'])
    end
    @graph.assert("[dcterms:title]", title)
    if @marc['210']
      @graph.assert("[bibo:shortTitle]", @marc['210']['a'].strip_trailing_punct)
    end
    if @marc['020'] && @marc['020']['a']
      isbn = ISBN_Tools.cleanup(@marc['020']['a'].strip_trailing_punct)
      if ISBN_Tools.is_valid?(isbn)
        if isbn.length == 10
          @graph.assert("[bibo:isbn10]",isbn)
          @graph.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{isbn}#book")
          @graph.assert("[bibo:isbn13]", ISBN_Tools.isbn10_to_isbn13(isbn))
        else
          @graph.assert("[bibo:isbn13]",isbn)
          @graph.assert("[bibo:isbn10]", ISBN_Tools.isbn13_to_isbn10(isbn))          
          @graph.relate("[owl:sameAs]", "http://purl.org/NET/book/isbn/#{ISBN_Tools.isbn13_to_isbn10(isbn)}#book")  
          isbn = ISBN_Tools.isbn13_to_isbn10(isbn) 
        end   
      end   
      @graph.relate("[dcterms:isVersionOf]", "http://xisbn.worldcat.org/webservices/xid/isbn/#{isbn}?method=getMetadata&format=xml&fl=*")   
    end

    if @marc['022'] && @marc['022']['a']
      @graph.assert("[bibo:issn]", @marc['022']['a'].strip_trailing_punct)
      @graph.relate("[dcterms:isVersionOf]", "http://xissn.worldcat.org/webservices/xid/issn/#{@marc['022']['a'].strip_trailing_punct}?method=getForms&format=xml")
    end  

    subjects = @marc.find_all {|field| field.tag =~ /^6../}

    subjects.each do | subject |
      literal = subject_to_string(subject)
      authority = nil
      if !["653","690","691","696","697", "698", "699"].index(subject.tag) && subject.indicator2 =~ /^(0|1)$/      

        authority = LinkedLCCN::LCSH.lookup_by_label(literal)
        if authority
          @graph.relate("[dcterms:subject]", authority)
        end
      end
      unless authority
        subj = RDFObject::Resource.new("http://purl.org/NET/lccn/subjects/#{CGI.escape(literal)}")
        subj.relate("[rdf:type]", "[skos:Concept]")
        subj.assert("[skos:prefLabel]", literal)
        @graph.relate("[dcterms:subject]", subj)
      end  
    end

    if @marc['250'] && @marc['250']['a']
      @graph.assert("[bibo:edition]", @marc['250']['a'])
    end
    if @marc['246'] && @marc['246']['a']
      @graph.assert("[rda:parallelTitleProper]", @marc['246']['a'].strip_trailing_punct)
    end
    if @marc['767'] && @marc['767']['t']
      @graph.assert("[rda:parallelTitleProper]", @marc['767']['t'].strip_trailing_punct)
    end  

    if @marc['100']
      if viaf = LinkedLCCN::VIAF.lookup_by_name(@marc['100'])
        @viaf << {:type=>:creator, :resource=>viaf, :cache=>viaf.to_xml(2)}
        relator_to_rdf(@marc['100']).each do | relator |
          @graph.relate(relator, viaf)
        end
      end
    end
    auths = @marc.find_all {|f| f.tag == '700'}
    auths.each do | auth |
      if viaf = LinkedLCCN::VIAF.lookup_by_name(auth)
        @viaf << {:type=>:creator, :resource=>viaf, :cache=>viaf.to_xml(2)}
        relator_to_rdf(auth).each do | relator |
          @graph.relate(relator, viaf)
        end 
      end
    end   

    links = @marc.find_all{|f| f.tag == '856'} 
    links.each do | link |
      if link.indicator2 == "1"
        @graph.assert("[bibo:uri]", link['u']) if link['u']
      end
    end
    @marc.languages.each do | lang |
      next unless lang
      @graph.relate("[dcterms:language]", "http://purl.org/NET/marccodes/languages/#{lang.three_code}#lang")
    end

    if @marc.publication_country && @marc.publication_country !~ /\|/
      @graph.relate("[rda:placeOfPublication]", "http://purl.org/NET/marccodes/countries/#{@marc.publication_country}#location")
    end

    gacs = @marc.find_all{|f| f.tag == '043'}
    gacs.each do | gac |
      l = gac.find_all{|f| f.code == 'a'}
      l.each do | subfield |
        @graph.relate("[foaf:topic]","http://purl.org/NET/marccodes/gacs/#{subfield.value.sub(/-*$/,"")}#location")
      end
    end
  end  
  
  def fetch_lodthing
    if @graph.bibo && @graph.bibo['isbn10']
      @graph.bibo['isbn10'].each do | isbn |
        library_thing = RDFObject::Resource.new("http://dilettantes.code4lib.org/LODThing/isbns/#{isbn}#book") 
        begin
          collection = library_thing.describe
          @graph.relate("[owl:sameAs]", library_thing)
        rescue RuntimeError
        end        
      end
    end
  end   
  
  def queue
    Delayed::Job.enqueue self
  end
  
  def to_json
    cache_rdf
    cache = {:lccn=>@lccn, :rdf=>@cached_rdf, :marc=>Base64.encode64(@marc.to_marc), :viaf=>[], :uri=>@graph.uri}
    @viaf.each do | viaf |
      cache[:viaf] << {:type=>viaf[:type], :rdf=>viaf[:cache], :uri=>viaf[:resource].uri}
    end
    cache.to_json
  end
  
  def self.new_from_json(json)
    lccn = self.new(json["lccn"])
    
    marc = MARC::ForgivingReader.new(StringIO.new(Base64.decode64(json["marc"])))
    marc.each {|m| lccn.marc = m }
    collection = RDFObject::Parser.parse(json["rdf"], :format=>"rdfxml")
    lccn.graph = collection["http://purl.org/NET/lccn/#{json["lccn"]}#i"]
    lccn.viaf = []
    json["viaf"].each do |viaf|
      v_collection = RDFObject::Parser.parse(viaf["rdf"], "rdfxml")
      lccn.viaf << {:type=>viaf["type"], :resource=>v_collection[viaf["uri"]], :cache=>viaf["rdf"]}
    end
    lccn
  end
    
  def background_tasks
#    @marc = MARC::Record.new_from_record(@marc)
#    collection = RDFObject::Parser.parse(@cached_rdf, :format=>"rdfxml")    
#    @graph = collection[@graph.uri]
#    @viaf.each do | viaf |
#      if viaf[:cache]
#        c = RDFObject::Parser.parse(viaf[:cache], :format=>"rdfxml")
#        viaf[:resource] = c[viaf[:resource].uri]
#      end
#      @graph.assertions.each_pair do |pred, obj|
#        next unless obj.respond_to?(:uri)
#        if obj.uri == viaf[:resource].uri
#          [*@graph[pred]].delete(obj)
#          @graph.relate(pred, viaf[:resource])
#        end
#      end
#    end    
    advanced_rdf
  end    
end