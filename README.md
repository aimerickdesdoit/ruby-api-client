# API Client

## Utilisation

	require 'api_client'

	client = ApiClient.new 'search.twitter.com'
	data = client.get '/search.json', :q => '#api', :result_type => 'mixed'
	results = data['results']

### Cache

	require 'api_client'
	
	ApiClient.redis = Redis.new
	
	client = ApiClient.new 'search.twitter.com'
	data = client.cache 'search:api' do
	  client.get '/search.json', :q => '#api', :result_type => 'mixed'
	end
	results = data['results']