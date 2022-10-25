const AWS = require("aws-sdk");
const dynamo = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event, context) => {
  let body;
  let statusCode = 200;
  const headers = {
	"Content-Type": "application/json"
  };

	tableName = "parking-lot-table";

  try {
	switch (event.routeKey) {
  	case "DELETE /v1/items/{id}":
    	await dynamo
      	.delete({
        	TableName: tableName,
        	Key: {
          	id: atob(event.pathParameters.id)
        	}
      	})
      	.promise();
    	body = `Deleted item ${event.pathParameters.id}`;
    	break;
  	case "GET /v1/items":
    	body = await dynamo.scan({ TableName: tableName }).promise();
    	break;
  	case "PUT /v1/items":
    	let requestJSON = JSON.parse(event.body);
    	await dynamo
      	.put({
        	TableName: tableName,
        	Item: {
          	id: requestJSON.id
        	}
      	})
      	.promise();
    	body = `Put item ${requestJSON.id}`;
    	break;
  	default:
    	throw new Error(`Unsupported route: "${event.routeKey}"`);
	}
  } catch (err) {
	statusCode = 400;
	body = err.message;
  } finally {
	body = JSON.stringify(body);
  }

  return {
	statusCode,
	body,
	headers
  };
};
