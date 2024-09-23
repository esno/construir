#!@@BINDIR@@/fiddle

lfs = {
  root = os.getenv("CONSTRUIR_AQUI") or "."
}

local DEBUG = function(msg)
  _debug('\27[0m-> ' .. msg .. '\27[0m')
end

local MSG = function(msg)
  _info('\27[0m** ' .. msg .. '\27[0m')
end

local INFO = function(msg)
  _info('\27[1;37m== ' .. msg .. '\27[0m')
end

local ERROR = function(msg)
  _error('\27[0;31m--\27[0m ' .. msg)
end

local SUCCESS = function(msg)
  _notice('\27[0;32m++\27[0m ' .. msg)
end

local install = function(path, mode)
  local m = tonumber(mode, 8)
  local p = path:sub(1, 1) == "/" and "/" or ""

  local enoent = { type = "-" }
  for ent in path:gmatch("([^/]+)") do
    p = string.format("%s%s/", p, ent)
    local f = p:sub(1, p:len() - 1)
    if (stat(f) or enoent)["type"] == "-" and mkdir(f, m) == -1 then
      return nil, f
    end
  end
  return true
end

local run = function(cmd)
  local fds = { stdin = {}, stdout = {}, stderr = {} }
  fds.stdin.read, fds.stdin.write = pipe()
  fds.stdout.read, fds.stdout.write = pipe()
  fds.stderr.read, fds.stderr.write = pipe()

  local pid = fork()
  if pid then
    if pid == 0 then
      -- child
      close(fds.stdin.write)
      close(fds.stdout.read)
      close(fds.stderr.read)

      dup2(fds.stdin.read, 0)
      dup2(fds.stdout.write, 1)
      dup2(fds.stderr.write, 2)

      execvp(cmd);
    else
      -- parent
      close(fds.stdin.read)
      close(fds.stdout.write)
      close(fds.stderr.write)

      local status = waitpid(pid);
      return status, fds.stdout.read, fds.stderr.read
    end
  end
end

local semver = function(self)
  local v = self.version:gmatch("[^.%s]+")
  return v(), v(), v()
end

local git_checkout = function(task)
  local remote = task.arg.remote:gsub("(.*[/:])(.*)", "%2")
  local gitdir = string.format("%s/git/%s", lfs.downloads, task.arg.remote:gsub("[:@/]", "_"))
  local S = string.format("%s/%s/%s", lfs.build, task.pkg.name, remote)

  MSG(string.format("\27[0;33m%s/%s\27[0m unpack \27[0;34m%s -> %s\27[0m",
    task.pkg.name, task.pkg.version, remote, task.arg.rev))

  install(S, "0755")
  local status, stdout, stderr = run(string.format("git --git-dir=%s --work-tree=%s checkout %s",
    gitdir, S, task.arg.rev))

  local output = fdopen(stdout, "r"):read("a*")
  if status ~= 0 and output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print \27[0;34mstdout\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
  local output = fdopen(stderr, "r"):read("a*")
  if status ~= 0 and output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print \27[0;34mstderr\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
end

local git_clone = function(task)
  MSG(string.format("\27[0;33m%s/%s\27[0m fetch \27[0;34m%s\27[0m",
    task.pkg.name, task.pkg.version, task.arg.remote))

  local remote = task.arg.remote:gsub("[:@/]", "_")
  local gitdir = string.format("%s/git/%s", lfs.downloads, remote)

  local cmd
  if (stat(gitdir) or { type = "-" })["type"] == "d" then
    cmd = string.format("git --git-dir=%s fetch origin --tags --prune --prune-tags", gitdir)
  else
    cmd = string.format("git clone --bare --mirror %s %s", task.arg.remote, gitdir)
  end

  local status, stdout, stderr = run(cmd)

  local output = fdopen(stdout, "r"):read("a*")
  if status ~= 0 and output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print stdout\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
  local output = fdopen(stderr, "r"):read("a*")
  if status ~= 0 and output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print stderr\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
end

local add_task = function(tasks, name, action, task)
  local key = string.format("%s:%s", name, action)
  tasks[key] = tasks[key] or {}
  table.insert(tasks[key], task)
  return tasks
end

local parse = function(target)
  local fenv = { pkg = {} }
  setmetatable(fenv, { __index = _G })

  _ENV = fenv
  setmetatable(pkg, {
    __index = function(self, key)
      local meta = {
        major = function(self) return ({semver(self)})[1] end,
        minor = function(self) return ({semver(self)})[2] end,
        patch = function(self) return ({semver(self)})[3] end
      }

      if type(meta[key]) == "function" then return meta[key](self) end
    end
  })
  _ENV = _G

  local recipe, errmsg = loadfile(string.format("%s/%s.lua", lfs.recipes, target), "t", fenv)
  if not recipe then
    ERROR(string.format("\27[0;33m%s\27[0m recipe failed: \27[0;31m%s\27[0m", target, errmsg))
    return nil
  end
  DEBUG(string.format("\27[0;33m%s\27[0m parse recipe", target))
  recipe()

  local tasks = {}
  if fenv.pkg.scm then
    for _, v in pairs(fenv.pkg.scm.git or {}) do
      DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mgit_clone %s\27[0m", fenv.pkg.name, fenv.pkg.version, v.remote))
      add_task(tasks, fenv.pkg.name, "fetch", { pkg = fenv.pkg, task = git_clone, arg = v })
      DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mgit_checkout %s -> %s\27[0m",
        fenv.pkg.name, fenv.pkg.version, v.remote:gsub("(.*[/:])(.*)", "%2"), v.rev))
      local after = string.format("%s:fetch", fenv.pkg.name)
      add_task(tasks, fenv.pkg.name, "unpack", { pkg = fenv.pkg, task = git_checkout, arg = v, after = { after } })
    end
  end

  return tasks
end

function main()
  setloglvl(20)
  dofile(string.format("%s/conf/construir.lua", lfs.root))
  lfs.recipes = lfs.recipes or string.format("%s/recipes", lfs.root)
  lfs.downloads = lfs.downloads or string.format("%s/dl", lfs.root)
  lfs.build = lfs.build or string.format("%s/build", lfs.root)

  INFO("construir: a custom linux distribution of your needs")
  local target = arg[2]
  local tasks = parse(target)
  local amount = function(t)
    local amount = 0
    for k, v in pairs(t) do
      amount = amount + 1
    end
    return amount
  end

  while amount(tasks) > 0 do
    for k, queue in pairs(tasks or {}) do
      for i, v in pairs(queue or {}) do
        local ack = true
        for _, dep in pairs(v.after or {}) do
          if tasks[dep] then ack = false end
        end
        if ack then
          v.task(v)
          tasks[k][i] = nil
          if amount(tasks[k]) == 0 then tasks[k] = nil end
        end
      end
    end
  end
end
