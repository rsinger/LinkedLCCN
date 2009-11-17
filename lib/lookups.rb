def get_lcsh(subject_string)
  u = URI.parse("http://id.loc.gov/authorities/label/#{subject_string.gsub(/\s/,"%20")}")
  req = Net::HTTP::Get.new(u.path)
  res = Net::HTTP.start(u.host, u.port) {|http|
    http.request(req)
  }
  
  if res.code == "302"
    uri = res.header['location']
    concept = Resource.new(uri)
    concept.describe
    return concept
  end
  return nil
end

def dbtune_lookup(upc)
  uri = URI.parse("http://dbtune.org/musicbrainz/sparql")
  sparql = <<SPARQL
PREFIX mo: <http://purl.org/ontology/mo/>
DESCRIBE * WHERE {
  ?obj mo:barcode "#{upc}"
}
SPARQL
  uri.query = "query=#{CGI.escape(sparql)}"
  response = Net::HTTP.get uri
  resources = {:record=>nil, :release=>nil}
  collection = Parser.parse response
  return nil if collection.empty?
  releases = collection.find_by_predicate("[rdf:type]")
  releases.each do | r |
    break unless r.is_a?(Array)
    r.each do | release |
      next unless release.is_a?(Resource)
      resources[:release] = release if release['[mo:barcode]'] == upc
    end
  end
  records = collection.find_by_predicate("[mo:release]")
  records.each do | r |
    break unless r.is_a?(Array)
    r.each do | record |
      next unless record.is_a?(Resource)
      record.describe
      resources[:record] = record
    end
  end  
  resources
end

def dbtune_catalog_number_lookup(label, number)
  uri = URI.parse("http://dbtune.org/musicbrainz/sparql")
  sparql = <<SPARQL
PREFIX mo: <http://purl.org/ontology/mo/>
PREFIX vocab: <http://dbtune.org/musicbrainz/resource/vocab/>
DESCRIBE ?s WHERE {
?label vocab:alias ?labelname .
?s vocab:release_catno "#{number}" .
?s mo:release_label ?label .
FILTER regex(?labelname, "#{label}", "i")
}
SPARQL
  uri.query = "query=#{CGI.escape(sparql)}"
  response = Net::HTTP.get uri
  resources = {:record=>nil, :release=>nil}
  collection = Parser.parse response
  return nil if collection.empty?
  release = collection.find_by_predicate_and_object("http://dbtune.org/musicbrainz/resource/vocab/release_catno", number)
  resources[:release] = release.values if release
  records = collection.find_by_predicate("[mo:release]")
  records.values.each do | record |
    record.describe
  end
  resources[:record] = records.values
  resources
end

def openlibrary_lookup(lccn)
  uri = URI.parse "http://openlibrary.org/query.json?type=/type/edition&lccn=#{CGI.escape(lccn)}&*="
  response = JSON.parse(Net::HTTP.get(uri))
  return nil if response.empty?
  return response
end

def linkedmdb_lookup(title)

sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX movie: <http://data.linkedmdb.org/resource/movie/>
PREFIX dc: <http://purl.org/dc/terms/>
DESCRIBE * WHERE {
 ?obj rdf:type movie:film .
 ?obj dc:title ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://data.linkedmdb.org/sparql?query=#{CGI.escape(sparql)}"
  response = HTTPClient.fetch(uri)
  collection = XMLParser.parse response
  return nil if collection.empty?
  resources = collection.find_by_predicate("[rdf:type]")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      [*resource['[rdf:type]']].each do | type |
        return resource if type.uri == "http://data.linkedmdb.org/resource/movie/film"
      end
    end
  end
  nil
end

def freebase_film_lookup(title, year=nil)
  
  resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/film/film")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def dbpedia_film_lookup(title)
 
sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
DESCRIBE * WHERE {
?obj rdf:type <http://dbpedia.org/ontology/Film> .
?obj foaf:name ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
  response = HTTPClient.fetch(uri)
  collection = XMLParser.parse response
  return nil if collection.empty?
  resources = collection.find_by_predicate("[rdf:type]")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      [*resource['[rdf:type]']].each do | type |
        return resource if type.uri == "http://dbpedia.org/ontology/Film"
      end
    end
  end
  nil
end

def viaf_lookup(name)
  client = SRU::Client.new("http://viaf.org/search")
  opts = {:maximumRecords=>5, :startRecord=>1, :recordSchema=>"http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
  name_values = []
  name.each do | subfield |
    next if (subfield.code == 't') or (subfield.code == '4')
    name_values << subfield.value
  end
  results = client.search_retrieve "local.names all \"#{name_values.join(" ").strip_trailing_punct}\"", opts
  results.each do | result |
    rdf = result.root.elements['/searchRetrieveResponse/records/record/recordData/'].children
    collection = Parser.parse(rdf.to_s)
    resources = collection.find_by_predicate("[foaf:name]")
    resources.each do | r |
      break unless r.is_a?(Array)
      r.each do | resource |
        next unless resource.is_a?(Resource)
        if results.number_of_records == 1
          return resource
        end
        [*resource['[foaf:name]']].each do | name |
          return resource if name == name_values.join(" ").strip_trailing_punct
        end
      end
    end
  end
  nil
end


def freebase_book_lookup(title, author)
  fuzz_auth = author['a'].split(",")[0]
  resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/book/written_work")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def freebase_journal_lookup(title, issn=nil)
  resources = Ken.all(:name=>title, :ISSN=>issn, :type=>"/book/periodical")
  matched_resource = nil
  resources.each do | resource |
    if resources.length == 1
      matched_resource = resource
      break
    end
  end
  if matched_resource
    r = Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
    return r
  else
    return nil
  end
end

def dbpedia_journal_lookup(title, issn)
 
sparql = <<SPARQL
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX dbpedia: <http://dbpedia.org/property/>
DESCRIBE * WHERE {
?obj dbpedia:issn ?issn FILTER regex(?issn, "#{issn}", "i") .
?obj rdfs:label ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
  uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
  response = HTTPClient.fetch(uri)
  collection = XMLParser.parse response
  return nil if collection.empty?
  resources = collection.find_by_predicate("http://dbpedia.org/property/issn")
  resources.each do | r |
    break unless r.is_a?(Array)
    r.each do | resource |
      next unless resource.is_a?(Resource)
      return resource
    end
  end
  nil
end

def loc_creator_search(creator)
  client = SRU::Client.new("http://z3950.loc.gov:7090/Voyager")
  client.version = "1.1"
  queries = []
  [*creator.foaf['name']].each do | name |
    queries << "(dc.creator all \"#{name}\")"
  end
  opts = {:startRecord=>1, :maximumRecords=>50, :recordSchema=>'marcxml'}
  queries.each do | slice |
    results = client.search_retrieve(slice, opts)
    results.doc.each_element('//datafield[@tag="010"]/subfield[@code="a"]') do | lccn_tag |
      lccn = lccn_tag.get_text.value.strip
      creator.relate("[foaf:made]", "http://purl.org/NET/lccn/#{CGI.escape(lccn)}#i")      
    end
  end
end

def get_marc(lccn)
  uri = URI.parse "http://lccn.loc.gov/#{lccn.gsub(/\s/,"%20")}/marcxml"
  req = Net::HTTP::Get.new(uri.path)
  res = Net::HTTP.start(uri.host, uri.port) {|http|
    http.request(req)
  }
  return nil unless res.code == "200"
  record = nil
  marc = MARC::XMLReader.new(StringIO.new(res.body))
  marc.each {|rec| record = MARC::Record.new_from_marc(rec.to_marc)}
  record
end
