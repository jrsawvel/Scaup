curl -X PUT 'http://127.0.0.1:9200/_river/scaupdvlp1/_meta' -d '{ "type" : "couchdb", "couchdb" : { "host" : "localhost", "port" : 5984, "db" : "scaupdvlp1", "filter" : null }, "index" : { "index" : "scaupdvlp1", "type" : "scaupdvlp1", "bulk_size" : "100", "bulk_timeout" : "10ms" } }'

