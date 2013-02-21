# API Client

## Utilisation

	require 'api_client'

	client = ApiClient.new 'search.twitter.com'
	results = client.get '/search.json', :q => '#api', :result_type => 'mixed'