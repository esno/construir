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
      return fds.stdout.read, fds.stderr.read
    end
  end
end

local semver = function(self)
  local v = self.version:gmatch("[^.%s]+")
  return v(), v(), v()
end

local git_clone = function(task)
  MSG(string.format("\27[0;33m%s/%s\27[0m fetch \27[0;34m%s\27[0m", task.pkg.name, task.pkg.version, task.remote))
  local cmd
  if stat(string.format("%s/git/%s", lfs.downloads, task.pkg.name))["type"] == "d" then
    cmd = string.format("git --git-dir=%s/git/%s fetch origin --tags --prune --prune-tags", lfs.downloads, task.pkg.name)
  else
    cmd = string.format("git clone --bare --mirror %s %s/git/%s", task.remote, lfs.downloads, task.pkg.name)
  end

  local stdout, stderr = run(cmd)

  local output = fdopen(stdout, "r"):read("a*")
  if output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print stdout\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
  local output = fdopen(stderr, "r"):read("a*")
  if output ~= "" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m print stderr\27[0m", task.pkg.name, task.pkg.version))
    print(output:gsub("\n$", ""))
  end
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
      table.insert(tasks, { pkg = fenv.pkg, task = git_clone, remote = v.remote })
    end
  end

  return tasks
end

function main()
  setloglvl(20)
  dofile(string.format("%s/conf/construir.lua", lfs.root))
  lfs.recipes = lfs.recipes or string.format("%s/recipes", lfs.root)
  lfs.downloads = lfs.downloads or string.format("%s/dl", lfs.root)

  INFO("construir: a custom linux distribution of your needs")
  local target = arg[2]
  local tasks = parse(target)

  for _, v in pairs(tasks or {}) do
    v.task(v)
  end
end
