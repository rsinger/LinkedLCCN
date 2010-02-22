class LinkedLCCN::LibraryOfCongress
  def self.creator_search(creator)
    client = SRU::Client.new("http://z3950.loc.gov:7090/Voyager")
    client.version = "1.1"
    queries = []
    [*creator.foaf['name']].each do | name |
      queries << "(dc.creator all \"#{name}\")"
    end
    opts = {:maximumRecords=>50, :recordSchema=>'marcxml'}
    queries.each do | slice |
      i = 0
      total = 50
      while i < total
        opts[:startRecord] = i+1
        results = client.search_retrieve(slice, opts)
        results.doc.each_element('//datafield[@tag="010"]/subfield[@code="a"]') do | lccn_tag |
          lccn = lccn_tag.get_text.value.strip.gsub(/\s/,"")
          creator.relate("[foaf:made]", "http://purl.org/NET/lccn/#{CGI.escape(lccn)}#i")      
        end
        total = results.number_of_records
        i += 50
      end
    end
  end  
  
  def self.lookup_chronam(lccn)
    u = URI.parse("http://chroniclingamerica.loc.gov/lccn/#{lccn}.rdf")
    req = Net::HTTP::Get.new(u.path)
    res = Net::HTTP.start(u.host, u.port) {|http|
      http.request(req)
    }

    if res.code == "200"    
      collection = RDFObject::Parser.parse(res.body, "rdfxml")
      if collection["http://chroniclingamerica.loc.gov/lccn/#{lccn}#title"]
        return collection["http://chroniclingamerica.loc.gov/lccn/#{lccn}#title"]
      end
    end
    nil
  end
end