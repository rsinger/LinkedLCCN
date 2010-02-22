class LinkedLCCN::DBTune
  def self.lookup_by_barcode(upc)
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
    collection = RDFObject::Parser.parse response
    return nil if collection.empty?
    releases = collection.find_by_predicate("[rdf:type]")
    releases.each do | r |
      break unless r.is_a?(Array)
      r.each do | release |
        next unless release.is_a?(RDFObject::Resource)
        resources[:release] = release if release['[mo:barcode]'] == upc
      end
    end
    records = collection.find_by_predicate("[mo:release]")
    records.each do | r |
      break unless r.is_a?(Array)
      r.each do | record |
        next unless record.is_a?(RDFObject::Resource)
        record.describe
        resources[:record] = record
      end
    end  
    resources
  end

  def self.lookup_by_catalog_number(label, number)
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
    puts uri.to_s
    begin
      response = Net::HTTP.get uri
    rescue Timeout::Error
      return
    end
    resources = {:record=>nil, :release=>nil}
    collection = RDFObject::Parser.parse response
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
end
  