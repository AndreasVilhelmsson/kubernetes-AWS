var builder = WebApplication.CreateBuilder(args);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();
app.UseSwagger();
app.UseSwaggerUI();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

var todos = new List<string> { "buy milk", "ship app" };
app.MapGet("/api/todos", () => Results.Ok(todos));
app.MapPost("/api/todos", async (HttpContext ctx) =>
{
	using var sr = new StreamReader(ctx.Request.Body);
	var text = (await sr.ReadToEndAsync()).Trim('"');
	if (!string.IsNullOrWhiteSpace(text)) todos.Add(text);
	return Results.Created($"/api/todos/{todos.Count - 1}", text);
});

app.Run();
