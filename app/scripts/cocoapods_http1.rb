# Loaded into CocoaPods via RUBYOPT by build-local.sh. Not part of upstream.
#
# CocoaPods' CDN source asks for HTTP/2 (cdn_source.rb passes
# :http_version => :httpv2_0). Against its CDNs (cdn.cocoapods.org, which
# fronts cdn.jsdelivr.net), macOS's libcurl
# (8.7.1, SecureTransport) fails those requests with "Error in the HTTP2
# framing layer" -- a different podspec each run, so `pod install` never
# finishes. The same URLs load fine over HTTP/1.1. Only requests that asked
# for HTTP/2 -- which in CocoaPods are the CDN spec fetches -- are changed.
begin
  require "typhoeus"
  module OmiForceHttp11
    def initialize(base_url, options = {})
      if options[:http_version] == :httpv2_0
        options = options.merge(http_version: :httpv1_1)
      end
      super(base_url, options)
    end
  end
  Typhoeus::Request.prepend(OmiForceHttp11)
rescue LoadError
  # A Ruby without Typhoeus is not running CocoaPods; nothing to change.
end
