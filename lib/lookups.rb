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

def openlibrary_lookup(lccn)
  uri = URI.parse "http://openlibrary.org/query.json?type=/type/edition&lccn=#{lccn}&*="
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

def get_marc(lccn)
  uri = URI.parse "http://lccn.loc.gov/#{lccn}/marcxml"
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