class LinkedLCCN::LCSH
  def self.lookup_by_label(label)
    begin
      u = Addressable::URI.parse("http://id.loc.gov/authorities/label/#{label.gsub(/\s/,"%20")}")
      u.normalize!
    rescue URI::InvalidURIError
      return nil
    end
    req = Net::HTTP::Get.new(u.path)
    res = Net::HTTP.start(u.host, u.port) {|http|
      http.request(req)
    }

    if res.code == "302"
      uri = res.header['location']
      concept = RDFObject::Resource.new(uri)
      concept.describe
      return concept
    end
    return nil        
  end
end