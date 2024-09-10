#!@@BINDIR@@/fiddle

lfs = {
  root = os.getenv("CONSTRUIR_AQUI") or "."
}

local dat = function(msg)
  print('\27[0m-- ' .. msg .. '\27[0m')
end

local wat = function(msg)
  print('\27[1;37m== ' .. msg .. '\27[0m')
end

local nak = function(msg)
  print('\27[0;31m--\27[0m ' .. msg)
end

local ack = function(msg)
  print('\27[0;32m++\27[0m ' .. msg)
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
      fds.stdin.write:close()
      fds.stdout.read:close()
      fds.stderr.read:close()

      dup2(fds.stdin.read, 0)
      dup2(fds.stdout.write, 1)
      dup2(fds.stderr.write, 2)

      execvp(cmd);
    else
      -- parent
      fds.stdin.read:close()
      fds.stdout.write:close()
      fds.stderr.write:close()

      status = waitpid(pid);
      print(fds.stdout.read:read("a*"))
    end
  end
end

local semver = function(self)
  local v = self.version:gmatch("[^.%s]+")
  return v(), v(), v()
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

  local recipe = loadfile(string.format("%s/%s/%s.lua", lfs.root, lfs.recipes, target), "t", fenv)
  if not recipe then
    nak(string.format("\27[0;33m%s\27[0m recipe failed", target))
    return nil
  end
  recipe()
  ack(string.format("\27[0;33m%s/%s\27[0m recipe parsed", target, fenv.pkg.version))

  return fenv.pkg
end

local fetch = function(pkg)
  for _, v in pairs(pkg.scm.git or {}) do
    dat(string.format("\27[0;33m%s/%s\27[0m fetch \27[0;34m%s\27[0m", pkg.name, pkg.version, v.remote))
    run(string.format("git clone --bare --mirror %s %s/%s/git/%s", v.remote, lfs.root, lfs.downloads, pkg.name))
  end
end

dofile(string.format("%s/conf/construir.lua", lfs.root))
lfs.recipes = lfs.recipes or "recipes"
lfs.downloads = lfs.downloads or "dl"

wat("construir: a custom linux distribution of your needs")
local target = arg[2]
local pkg = parse(target)

if pkg.scm then
  fetch(pkg)
end
