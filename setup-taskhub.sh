#!/usr/bin/env bash
set -euo pipefail

# Config
GIT_REMOTE="https://github.com/somanathpujari/mydocs.git"
SOLUTION="TaskHub"
API_KEY="secret123"
REPO_DIR="mydocs"
PROJECT_DIR="TaskHub" # subfolder inside repo

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1. Please install and re-run." >&2; exit 1; }; }

need_cmd git
need_cmd dotnet

echo "Cloning repo: $GIT_REMOTE"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Existing repo dir '$REPO_DIR' detected. Pulling latest..."
  (cd "$REPO_DIR" && git pull --rebase)
else
  git clone "$GIT_REMOTE" "$REPO_DIR"
fi

cd "$REPO_DIR"

# Ensure main branch
if git show-ref --verify --quiet refs/heads/main; then
  git checkout main
else
  # fallback if default branch is not main
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  echo "Using branch: $CURRENT_BRANCH"
fi

mkdir -p "$PROJECT_DIR/src"
cd "$PROJECT_DIR/src"

# Create solution and projects
dotnet new sln -n "$SOLUTION"
dotnet new classlib -n "$SOLUTION.Domain" -o "$SOLUTION.Domain"
dotnet new classlib -n "$SOLUTION.Application" -o "$SOLUTION.Application"
dotnet new classlib -n "$SOLUTION.Infrastructure" -o "$SOLUTION.Infrastructure"
dotnet new webapi   -n "$SOLUTION.Api" -o "$SOLUTION.Api" --no-https

dotnet sln add "$SOLUTION.Domain/$SOLUTION.Domain.csproj"
dotnet sln add "$SOLUTION.Application/$SOLUTION.Application.csproj"
dotnet sln add "$SOLUTION.Infrastructure/$SOLUTION.Infrastructure.csproj"
dotnet sln add "$SOLUTION.Api/$SOLUTION.Api.csproj"

dotnet add "$SOLUTION.Application/$SOLUTION.Application.csproj" reference "../$SOLUTION.Domain/$SOLUTION.Domain.csproj"
dotnet add "$SOLUTION.Infrastructure/$SOLUTION.Infrastructure.csproj" reference "../$SOLUTION.Domain/$SOLUTION.Domain.csproj" "../$SOLUTION.Application/$SOLUTION.Application.csproj"
dotnet add "$SOLUTION.Api/$SOLUTION.Api.csproj" reference "../$SOLUTION.Application/$SOLUTION.Application.csproj" "../$SOLUTION.Infrastructure/$SOLUTION.Infrastructure.csproj" "../$SOLUTION.Domain/$SOLUTION.Domain.csproj"

dotnet add "$SOLUTION.Api/$SOLUTION.Api.csproj" package Swashbuckle.AspNetCore --version 6.5.0

# ---- Write files (Domain) ----
mkdir -p "$SOLUTION.Domain/Entities" "$SOLUTION.Domain/Enums"

cat > "$SOLUTION.Domain/Entities/User.cs" <<'EOF'
namespace TaskHub.Domain.Entities;

public class User
{
    public int Id { get; private set; }
    public string Name { get; private set; } = string.Empty;
    public string Email { get; private set; } = string.Empty;

    public User(int id, string name, string email)
    {
        Id = id;
        Update(name, email);
    }

    public void Update(string name, string email)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("Name is required");
        if (string.IsNullOrWhiteSpace(email)) throw new ArgumentException("Email is required");
        Name = name.Trim();
        Email = email.Trim();
    }
}
EOF

cat > "$SOLUTION.Domain/Enums/TaskStatus.cs" <<'EOF'
namespace TaskHub.Domain.Enums;

public enum TaskStatus
{
    Pending = 0,
    InProgress = 1,
    Completed = 2
}
EOF

cat > "$SOLUTION.Domain/Enums/TaskPriority.cs" <<'EOF'
namespace TaskHub.Domain.Enums;

public enum TaskPriority
{
    Low = 0,
    Medium = 1,
    High = 2
}
EOF

cat > "$SOLUTION.Domain/Entities/TaskItem.cs" <<'EOF'
using TaskHub.Domain.Enums;

namespace TaskHub.Domain.Entities;

public class TaskItem
{
    public int Id { get; private set; }
    public string Title { get; private set; } = string.Empty;
    public string Description { get; private set; } = string.Empty;
    public TaskStatus Status { get; private set; }
    public TaskPriority Priority { get; private set; }
    public DateTime DueDate { get; private set; }
    public int UserId { get; private set; }

    public TaskItem(int id, string title, string description, TaskPriority priority, DateTime dueDate, int userId)
    {
        Id = id;
        Update(title, description, priority, dueDate, userId);
        Status = TaskStatus.Pending;
    }

    public void Update(string title, string description, TaskPriority priority, DateTime dueDate, int userId)
    {
        if (string.IsNullOrWhiteSpace(title)) throw new ArgumentException("Title is required");
        if (dueDate <= DateTime.UtcNow) throw new ArgumentException("Due date must be in the future");
        Title = title.Trim();
        Description = description?.Trim() ?? string.Empty;
        Priority = priority;
        DueDate = DateTime.SpecifyKind(dueDate, DateTimeKind.Utc);
        UserId = userId;
    }

    public void UpdateStatus(TaskStatus newStatus)
    {
        if (newStatus < Status) throw new InvalidOperationException("Cannot revert status");
        if (Status == TaskStatus.Pending && newStatus == TaskStatus.Completed)
            throw new InvalidOperationException("Must go through InProgress before Completed");

        Status = newStatus;
    }
}
EOF

# ---- Application layer ----
mkdir -p "$SOLUTION.Application/DTOs" "$SOLUTION.Application/Interfaces" "$SOLUTION.Application/Services" "$SOLUTION.Application/Common" "$SOLUTION.Application/Mapping"

cat > "$SOLUTION.Application/DTOs/UserDtos.cs" <<'EOF'
namespace TaskHub.Application.DTOs;

public record UserCreateDto(string Name, string Email);
public record UserUpdateDto(string Name, string Email);
public record UserDto(int Id, string Name, string Email);
EOF

cat > "$SOLUTION.Application/DTOs/TaskDtos.cs" <<'EOF'
using TaskHub.Domain.Enums;

namespace TaskHub.Application.DTOs;

public record TaskCreateDto(string Title, string Description, TaskPriority Priority, DateTime DueDate, int UserId);
public record TaskUpdateDto(string Title, string Description, TaskPriority Priority, DateTime DueDate, int UserId);
public record TaskStatusUpdateDto(TaskStatus Status);
public record TaskDto(int Id, string Title, string Description, TaskStatus Status, TaskPriority Priority, DateTime DueDate, int UserId);
EOF

cat > "$SOLUTION.Application/DTOs/QueryParams.cs" <<'EOF'
using TaskHub.Domain.Enums;

namespace TaskHub.Application.DTOs;

public class TaskQuery
{
    public TaskStatus? Status { get; set; }
    public TaskPriority? Priority { get; set; }
    public DateTime? DueFrom { get; set; }
    public DateTime? DueTo { get; set; }
    public string? SortBy { get; set; }
    public string? SortDir { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}
EOF

cat > "$SOLUTION.Application/Common/PagedResult.cs" <<'EOF'
namespace TaskHub.Application.Common;

public class PagedResult<T>
{
    public IReadOnlyList<T> Items { get; }
    public int Total { get; }
    public int Page { get; }
    public int PageSize { get; }

    public PagedResult(IReadOnlyList<T> items, int total, int page, int pageSize)
    {
        Items = items;
        Total = total;
        Page = page;
        PageSize = pageSize;
    }
}
EOF

cat > "$SOLUTION.Application/Interfaces/IUserRepository.cs" <<'EOF'
using TaskHub.Domain.Entities;

namespace TaskHub.Application.Interfaces;

public interface IUserRepository
{
    Task<IReadOnlyList<User>> GetAllAsync();
    Task<User?> GetByIdAsync(int id);
    Task<User> AddAsync(User user);
    Task UpdateAsync(User user);
    Task DeleteAsync(int id);
    Task<bool> ExistsAsync(int id);
}
EOF

cat > "$SOLUTION.Application/Interfaces/ITaskRepository.cs" <<'EOF'
using TaskHub.Domain.Entities;

namespace TaskHub.Application.Interfaces;

public interface ITaskRepository
{
    Task<IReadOnlyList<TaskItem>> GetAllAsync();
    Task<TaskItem?> GetByIdAsync(int id);
    Task<TaskItem> AddAsync(TaskItem task);
    Task UpdateAsync(TaskItem task);
    Task DeleteAsync(int id);
    Task<IReadOnlyList<TaskItem>> GetByUserIdAsync(int userId);
}
EOF

cat > "$SOLUTION.Application/Interfaces/IUserService.cs" <<'EOF'
using TaskHub.Application.DTOs;

namespace TaskHub.Application.Interfaces;

public interface IUserService
{
    Task<IReadOnlyList<UserDto>> GetAllAsync();
    Task<UserDto?> GetByIdAsync(int id);
    Task<UserDto> CreateAsync(UserCreateDto dto);
    Task<UserDto?> UpdateAsync(int id, UserUpdateDto dto);
    Task<bool> DeleteAsync(int id);
}
EOF

cat > "$SOLUTION.Application/Interfaces/ITaskService.cs" <<'EOF'
using TaskHub.Application.DTOs;
using TaskHub.Application.Common;

namespace TaskHub.Application.Interfaces;

public interface ITaskService
{
    Task<PagedResult<TaskDto>> GetAllAsync(TaskQuery query);
    Task<TaskDto?> GetByIdAsync(int id);
    Task<IReadOnlyList<TaskDto>> GetByUserIdAsync(int userId);
    Task<TaskDto> CreateAsync(TaskCreateDto dto);
    Task<TaskDto?> UpdateAsync(int id, TaskUpdateDto dto);
    Task<TaskDto?> UpdateStatusAsync(int id, TaskStatusUpdateDto dto);
    Task<bool> DeleteAsync(int id);
    Task<string> ExportCsvAsync(TaskQuery query);
}
EOF

cat > "$SOLUTION.Application/Mapping/MappingExtensions.cs" <<'EOF'
using TaskHub.Application.DTOs;
using TaskHub.Domain.Entities;

namespace TaskHub.Application.Mapping;

public static class MappingExtensions
{
    public static UserDto ToDto(this User u) => new(u.Id, u.Name, u.Email);
    public static TaskDto ToDto(this TaskItem t) =>
        new(t.Id, t.Title, t.Description, t.Status, t.Priority, t.DueDate, t.UserId);
}
EOF

cat > "$SOLUTION.Application/Services/UserService.cs" <<'EOF'
using TaskHub.Application.DTOs;
using TaskHub.Application.Interfaces;
using TaskHub.Application.Mapping;
using TaskHub.Domain.Entities;

namespace TaskHub.Application.Services;

public class UserService : IUserService
{
    private readonly IUserRepository _repo;
    public UserService(IUserRepository repo) => _repo = repo;

    public async Task<IReadOnlyList<UserDto>> GetAllAsync()
        => (await _repo.GetAllAsync()).Select(u => u.ToDto()).ToList();

    public async Task<UserDto?> GetByIdAsync(int id)
    {
        var u = await _repo.GetByIdAsync(id);
        return u?.ToDto();
    }

    public async Task<UserDto> CreateAsync(UserCreateDto dto)
    {
        var created = await _repo.AddAsync(new User(0, dto.Name, dto.Email));
        return created.ToDto();
    }

    public async Task<UserDto?> UpdateAsync(int id, UserUpdateDto dto)
    {
        var u = await _repo.GetByIdAsync(id);
        if (u is null) return null;
        u.Update(dto.Name, dto.Email);
        await _repo.UpdateAsync(u);
        return u.ToDto();
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var exists = await _repo.ExistsAsync(id);
        if (!exists) return false;
        await _repo.DeleteAsync(id);
        return true;
    }
}
EOF

cat > "$SOLUTION.Application/Services/TaskService.cs" <<'EOF'
using System.Text;
using TaskHub.Application.Common;
using TaskHub.Application.DTOs;
using TaskHub.Application.Interfaces;
using TaskHub.Application.Mapping;
using TaskHub.Domain.Entities;
using TaskHub.Domain.Enums;

namespace TaskHub.Application.Services;

public class TaskService : ITaskService
{
    private readonly ITaskRepository _tasks;
    private readonly IUserRepository _users;

    public TaskService(ITaskRepository tasks, IUserRepository users)
    {
        _tasks = tasks;
        _users = users;
    }

    public async Task<PagedResult<TaskDto>> GetAllAsync(TaskQuery query)
    {
        var items = await _tasks.GetAllAsync();

        if (query.Status.HasValue) items = items.Where(t => t.Status == query.Status.Value).ToList();
        if (query.Priority.HasValue) items = items.Where(t => t.Priority == query.Priority.Value).ToList();
        if (query.DueFrom.HasValue) items = items.Where(t => t.DueDate >= query.DueFrom.Value).ToList();
        if (query.DueTo.HasValue) items = items.Where(t => t.DueDate <= query.DueTo.Value).ToList();

        var sortBy = (query.SortBy ?? "duedate").ToLowerInvariant();
        var sortDir = (query.SortDir ?? "asc").ToLowerInvariant();
        items = sortBy switch
        {
            "priority" => (sortDir == "desc" ? items.OrderByDescending(t => t.Priority) : items.OrderBy(t => t.Priority)).ToList(),
            _ => (sortDir == "desc" ? items.OrderByDescending(t => t.DueDate) : items.OrderBy(t => t.DueDate)).ToList(),
        };

        var total = items.Count;
        var page = Math.Max(1, query.Page);
        var pageSize = Math.Clamp(query.PageSize, 1, 200);
        var paged = items.Skip((page - 1) * pageSize).Take(pageSize).Select(t => t.ToDto()).ToList();

        return new PagedResult<TaskDto>(paged, total, page, pageSize);
    }

    public async Task<TaskDto?> GetByIdAsync(int id)
    {
        var t = await _tasks.GetByIdAsync(id);
        return t?.ToDto();
    }

    public async Task<IReadOnlyList<TaskDto>> GetByUserIdAsync(int userId)
    {
        var list = await _tasks.GetByUserIdAsync(userId);
        return list.Select(t => t.ToDto()).ToList();
    }

    public async Task<TaskDto> CreateAsync(TaskCreateDto dto)
    {
        if (!await _users.ExistsAsync(dto.UserId))
            throw new ArgumentException($"User {dto.UserId} does not exist");

        var task = new TaskItem(0, dto.Title, dto.Description, dto.Priority, dto.DueDate, dto.UserId);
        var created = await _tasks.AddAsync(task);
        return created.ToDto();
    }

    public async Task<TaskDto?> UpdateAsync(int id, TaskUpdateDto dto)
    {
        var t = await _tasks.GetByIdAsync(id);
        if (t is null) return null;

        if (!await _users.ExistsAsync(dto.UserId))
            throw new ArgumentException($"User {dto.UserId} does not exist");

        t.Update(dto.Title, dto.Description, dto.Priority, dto.DueDate, dto.UserId);
        await _tasks.UpdateAsync(t);
        return t.ToDto();
    }

    public async Task<TaskDto?> UpdateStatusAsync(int id, TaskStatusUpdateDto dto)
    {
        var t = await _tasks.GetByIdAsync(id);
        if (t is null) return null;

        t.UpdateStatus(dto.Status);
        await _tasks.UpdateAsync(t);
        return t.ToDto();
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var t = await _tasks.GetByIdAsync(id);
        if (t is null) return false;
        await _tasks.DeleteAsync(id);
        return true;
    }

    public async Task<string> ExportCsvAsync(TaskQuery query)
    {
        var data = await GetAllAsync(query);
        var sb = new StringBuilder();
        sb.AppendLine("Id,Title,Description,Status,Priority,DueDate,UserId");
        foreach (var t in data.Items)
        {
            var line = string.Join(",", new []
            {
                t.Id.ToString(),
                Quote(t.Title),
                Quote(t.Description),
                t.Status.ToString(),
                t.Priority.ToString(),
                t.DueDate.ToString("o"),
                t.UserId.ToString()
            });
            sb.AppendLine(line);
        }
        return sb.ToString();

        static string Quote(string s) => $"\"{s?.Replace("\"","\"\"")}\"";
    }
}
EOF

# ---- Infrastructure layer (in-memory repos) ----
mkdir -p "$SOLUTION.Infrastructure/Repositories"

cat > "$SOLUTION.Infrastructure/Repositories/InMemoryUserRepository.cs" <<'EOF'
using System.Collections.Concurrent;
using TaskHub.Application.Interfaces;
using TaskHub.Domain.Entities;

namespace TaskHub.Infrastructure.Repositories;

public class InMemoryUserRepository : IUserRepository
{
    private readonly ConcurrentDictionary<int, User> _store = new();
    private int _idSeq = 0;

    public Task<IReadOnlyList<User>> GetAllAsync()
        => Task.FromResult<IReadOnlyList<User>>(_store.Values.OrderBy(u => u.Id).ToList());

    public Task<User?> GetByIdAsync(int id)
        => Task.FromResult(_store.TryGetValue(id, out var u) ? u : null);

    public Task<User> AddAsync(User user)
    {
        var id = Interlocked.Increment(ref _idSeq);
        var created = new User(id, user.Name, user.Email);
        _store[id] = created;
        return Task.FromResult(created);
    }

    public Task UpdateAsync(User user)
    {
        _store[user.Id] = user;
        return Task.CompletedTask;
    }

    public Task DeleteAsync(int id)
    {
        _store.TryRemove(id, out _);
        return Task.CompletedTask;
    }

    public Task<bool> ExistsAsync(int id)
        => Task.FromResult(_store.ContainsKey(id));
}
EOF

cat > "$SOLUTION.Infrastructure/Repositories/InMemoryTaskRepository.cs" <<'EOF'
using System.Collections.Concurrent;
using TaskHub.Application.Interfaces;
using TaskHub.Domain.Entities;

namespace TaskHub.Infrastructure.Repositories;

public class InMemoryTaskRepository : ITaskRepository
{
    private readonly ConcurrentDictionary<int, TaskItem> _store = new();
    private int _idSeq = 0;

    public Task<IReadOnlyList<TaskItem>> GetAllAsync()
        => Task.FromResult<IReadOnlyList<TaskItem>>(_store.Values.OrderBy(t => t.Id).ToList());

    public Task<TaskItem?> GetByIdAsync(int id)
        => Task.FromResult(_store.TryGetValue(id, out var t) ? t : null);

    public Task<IReadOnlyList<TaskItem>> GetByUserIdAsync(int userId)
        => Task.FromResult<IReadOnlyList<TaskItem>>(_store.Values.Where(t => t.UserId == userId).OrderBy(t => t.Id).ToList());

    public Task<TaskItem> AddAsync(TaskItem task)
    {
        var id = Interlocked.Increment(ref _idSeq);
        var created = new TaskItem(id, task.Title, task.Description, task.Priority, task.DueDate, task.UserId);
        _store[id] = created;
        return Task.FromResult(created);
    }

    public Task UpdateAsync(TaskItem task)
    {
        _store[task.Id] = task;
        return Task.CompletedTask;
    }

    public Task DeleteAsync(int id)
    {
        _store.TryRemove(id, out _);
        return Task.CompletedTask;
    }
}
EOF

# ---- API layer ----
mkdir -p "$SOLUTION.Api/Controllers" "$SOLUTION.Api/Properties"

cat > "$SOLUTION.Api/Program.cs" <<'EOF'
using TaskHub.Application.Interfaces;
using TaskHub.Application.Services;
using TaskHub.Infrastructure.Repositories;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddSingleton<IUserRepository, InMemoryUserRepository>();
builder.Services.AddSingleton<ITaskRepository, InMemoryTaskRepository>();
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<ITaskService, TaskService>();

builder.Services.AddControllers()
    .AddJsonOptions(o => {
        o.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
    });

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

app.Use(async (context, next) =>
{
    var configKey = builder.Configuration["ApiKey"] ?? "secret123";
    var path = context.Request.Path.Value ?? string.Empty;

    if (path.StartsWith("/swagger") || path == "/")
    {
        await next();
        return;
    }

    if (!context.Request.Headers.TryGetValue("X-Api-Key", out var provided) || provided != configKey)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsync("Unauthorized");
        return;
    }
    await next();
});

app.MapControllers();
app.MapGet("/", () => Results.Redirect("/swagger"));

app.Run();
EOF

cat > "$SOLUTION.Api/Controllers/UsersController.cs" <<'EOF'
using Microsoft.AspNetCore.Mvc;
using TaskHub.Application.Interfaces;
using TaskHub.Application.DTOs;

namespace TaskHub.Api.Controllers;

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly IUserService _service;

    public UsersController(IUserService service) => _service = service;

    [HttpGet]
    public async Task<IActionResult> GetAll()
        => Ok(await _service.GetAllAsync());

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var u = await _service.GetByIdAsync(id);
        return u is null ? NotFound() : Ok(u);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] UserCreateDto dto)
    {
        var created = await _service.CreateAsync(dto);
        return CreatedAtAction(nameof(GetById), new { id = created.Id }, created);
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] UserUpdateDto dto)
    {
        var updated = await _service.UpdateAsync(id, dto);
        return updated is null ? NotFound() : Ok(updated);
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var ok = await _service.DeleteAsync(id);
        return ok ? NoContent() : NotFound();
    }
}
EOF

cat > "$SOLUTION.Api/Controllers/TasksController.cs" <<'EOF'
using Microsoft.AspNetCore.Mvc;
using TaskHub.Application.Interfaces;
using TaskHub.Application.DTOs;
using TaskHub.Domain.Enums;

namespace TaskHub.Api.Controllers;

[ApiController]
[Route("api")]
public class TasksController : ControllerBase
{
    private readonly ITaskService _service;

    public TasksController(ITaskService service) => _service = service;

    [HttpGet("tasks")]
    public async Task<IActionResult> GetAll(
        [FromQuery] TaskStatus? status,
        [FromQuery] TaskPriority? priority,
        [FromQuery] DateTime? dueFrom,
        [FromQuery] DateTime? dueTo,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortDir,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var query = new TaskQuery {
            Status = status,
            Priority = priority,
            DueFrom = dueFrom,
            DueTo = dueTo,
            SortBy = sortBy,
            SortDir = sortDir,
            Page = page,
            PageSize = pageSize
        };
        var result = await _service.GetAllAsync(query);
        Response.Headers["X-Total-Count"] = result.Total.ToString();
        return Ok(result);
    }

    [HttpGet("tasks/{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var t = await _service.GetByIdAsync(id);
        return t is null ? NotFound() : Ok(t);
    }

    [HttpGet("users/{id:int}/tasks")]
    public async Task<IActionResult> GetByUser(int id)
        => Ok(await _service.GetByUserIdAsync(id));

    [HttpPost("tasks")]
    public async Task<IActionResult> Create([FromBody] TaskCreateDto dto)
    {
        try
        {
            var created = await _service.CreateAsync(dto);
            return CreatedAtAction(nameof(GetById), new { id = created.Id }, created);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPut("tasks/{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] TaskUpdateDto dto)
    {
        try
        {
            var updated = await _service.UpdateAsync(id, dto);
            return updated is null ? NotFound() : Ok(updated);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPatch("tasks/{id:int}/status")]
    public async Task<IActionResult> UpdateStatus(int id, [FromBody] TaskStatusUpdateDto dto)
    {
        try
        {
            var updated = await _service.UpdateStatusAsync(id, dto);
            return updated is null ? NotFound() : Ok(updated);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("tasks/{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var ok = await _service.DeleteAsync(id);
        return ok ? NoContent() : NotFound();
    }

    [HttpGet("tasks/export/csv")]
    public async Task<IActionResult> ExportCsv(
        [FromQuery] TaskStatus? status,
        [FromQuery] TaskPriority? priority,
        [FromQuery] DateTime? dueFrom,
        [FromQuery] DateTime? dueTo,
        [FromQuery] string? sortBy,
        [FromQuery] string? sortDir,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 1000)
    {
        var query = new TaskQuery {
            Status = status,
            Priority = priority,
            DueFrom = dueFrom,
            DueTo = dueTo,
            SortBy = sortBy,
            SortDir = sortDir,
            Page = page,
            PageSize = pageSize
        };
        var csv = await _service.ExportCsvAsync(query);
        return File(System.Text.Encoding.UTF8.GetBytes(csv), "text/csv", "tasks.csv");
    }
}
EOF

cat > "$SOLUTION.Api/Properties/launchSettings.json" <<EOF
{
  "profiles": {
    "$SOLUTION.Api": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "applicationUrl": "http://localhost:5000",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ApiKey": "$API_KEY"
      }
    }
  }
}
EOF

# ---- README and .gitignore ----
cd ..
cat > "../README.md" <<'EOF'
# TaskHub - C# REST API

REST API for a Task Management system (.NET 8).

- Endpoints: Users CRUD, Tasks CRUD, user tasks, status PATCH, filters, sort, pagination, CSV export
- Layers: Domain, Application, Infrastructure, Api
- Auth: Header X-Api-Key: secret123
- Swagger: /swagger
- Run: dotnet run --project ./TaskHub.Api

Sample:
curl -X POST http://localhost:5000/api/users \
 -H "Content-Type: application/json" -H "X-Api-Key: secret123" \
 -d '{"name":"Ananya","email":"ananya@example.com"}'
EOF

cat > "../.gitignore" <<'EOF'
bin/
obj/
*.user
*.suo
*.DS_Store
.vscode/
.env
EOF

# ---- Commit and push ----
cd ..
git add .
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "Add TaskHub API (ASP.NET Core, layered architecture, Swagger, CSV export, header auth)"
fi

# Ensure we push to the current branch (main if exists)
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing to origin/$CURRENT_BRANCH ..."
git push -u origin "$CURRENT_BRANCH"

echo ""
echo "Done!"
echo "Run the API: dotnet run --project ./TaskHub/src/TaskHub.Api"
echo "Swagger: http://localhost:5000/swagger"
echo "Auth header: X-Api-Key: $API_KEY"

