using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

var mongoUri = builder.Configuration["MONGO_URI"] ?? "mongodb://root:changeme@localhost:27017/?authSource=admin";
var mongoClient = new MongoClient(mongoUri);
var database = mongoClient.GetDatabase("tododb");
var todosCollection = database.GetCollection<TodoItem>("todos");
builder.Services.AddSingleton(todosCollection);

var app = builder.Build();
app.UseCors();
app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/api/todos", async (IMongoCollection<TodoItem> collection) =>
{
    var todos = await collection.Find(_ => true).ToListAsync();
    return Results.Ok(todos);
});

app.MapPost("/api/todos", async (TodoCreateDto dto, IMongoCollection<TodoItem> collection) =>
{
    var todo = new TodoItem
    {
        Title = dto.Title,
        Completed = false,
        CreatedAt = DateTime.UtcNow
    };
    await collection.InsertOneAsync(todo);
    return Results.Created($"/api/todos/{todo.Id}", todo);
});

app.MapPut("/api/todos/{id}", async (string id, TodoUpdateDto dto, IMongoCollection<TodoItem> collection) =>
{
    var filter = Builders<TodoItem>.Filter.Eq(t => t.Id, id);
    var update = Builders<TodoItem>.Update
        .Set(t => t.Completed, dto.Completed);
    
    var result = await collection.UpdateOneAsync(filter, update);
    return result.MatchedCount > 0 ? Results.NoContent() : Results.NotFound();
});

app.MapDelete("/api/todos/{id}", async (string id, IMongoCollection<TodoItem> collection) =>
{
    var filter = Builders<TodoItem>.Filter.Eq(t => t.Id, id);
    var result = await collection.DeleteOneAsync(filter);
    return result.DeletedCount > 0 ? Results.NoContent() : Results.NotFound();
});

app.Run();

record TodoCreateDto(string Title);
record TodoUpdateDto(bool Completed);

class TodoItem
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public string? Id { get; set; }
    
    [BsonElement("title")]
    public string Title { get; set; } = string.Empty;
    
    [BsonElement("completed")]
    public bool Completed { get; set; }
    
    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; }
}
