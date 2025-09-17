# TaskHub - C# REST API
REST API for a Task Management system (.NET 8).
- Endpoints: Users CRUD, Tasks CRUD, user tasks, status PATCH, filters, sort, pagination, CSV export
- Layers: Domain, Application, Infrastructure, Api
- Auth: Header X-Api-Key: secret123
- Swagger: /swagger
- Run: dotnet run --project ./TaskHub/src/TaskHub.Api
Sample:
curl -X POST http://localhost:5000/api/users \
 -H "Content-Type: application/json" -H "X-Api-Key: secret123" \
 -d '{"name":"Ananya","email":"ananya@example.com"}'
