class LinkedLCCN::OpenLibrary
  def self.lookup(lccn)
    uri = URI.parse "http://openlibrary.org/query.json?type=/type/edition&lccn=#{CGI.escape(lccn)}&*="
    response = JSON.parse(Net::HTTP.get(uri))
    return nil if response.empty?
    return response
  end  
end