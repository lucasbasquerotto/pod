db.createCollection('fluentd');
db.createCollection('test2');

db.createUser(
	{
	  user: "fluent",
	  pwd: "Pa$$w0rd123",
	  roles: [ 
		{ role: "readWrite", db: "log" }
	  ]
	}
 )