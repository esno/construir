#!@@BINDIR@@/fiddle

lfs = {
  root = os.getenv("CONSTRUIR_AQUI") or ".",
  cc = {
    amd64 = "x86_64-linux-gnu",
    arm = "arm-linux-gnueabihf"
  }
}

local DEBUG = function(msg)
  fprintf(stdout, "\27[0m-> " .. msg .. "\27[0m\n")
end

local MSG = function(msg)
  fprintf(stdout, "\27[0m** " .. msg .. "\27[0m\n")
end

local INFO = function(msg)
  fprintf(stdout, "\27[1;37m== " .. msg .. "\27[0m\n")
end

local ERROR = function(msg)
  fprintf(stderr, "\27[0;31m--\27[0m " .. msg .. "\n")
end

local SUCCESS = function(msg)
  fprintf(stdout, "\27[0;32m++\27[0m " .. msg .. "\n")
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

local run = function(cmd, task)
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

      local lstdout = io.open(string.format("%s/%s.stdout", L, task.action), "a")
      local lstderr = io.open(string.format("%s/%s.stderr", L, task.action), "a")

      dup2(fds.stdin.read, 0)
      dup2(fileno(lstdout), 1)
      dup2(fileno(lstderr), 2)

      local success, errno, strerrno = execvp(cmd)
      lstdout:close()
      lstderr:close()

      dup2(fds.stdout.write, 1)
      dup2(fds.stderr.write, 2)

      if not success then
        print(string.format("\27[0;31m%s\27[0m", cmd));
        print(string.format("\27[0m%s (%d)", strerrno, errno))
        close(fds.stdin.read)
        close(fds.stdout.write)
        close(fds.stderr.write)
        os.exit(1)
      end
    else
      -- parent
      close(fds.stdin.read)
      close(fds.stdout.write)
      close(fds.stderr.write)

      local status = waitpid(pid);
      if status ~= 0 then
        local output = fdopen(fds.stdout.read, "r"):read("a*")
        if output ~= "" then
          DEBUG(string.format("\27[0;33m%s/%s\27[0m print \27[0;34mstdout\27[0m", task.pkg.name, task.pkg.version))
          print(output:gsub("\n$", ""))
        end
        local output = fdopen(fds.stderr.read, "r"):read("a*")
        if output ~= "" then
          ERROR(string.format("\27[0;33m%s/%s\27[0m print \27[0;31mstderr\27[0m", task.pkg.name, task.pkg.version))
          print(output:gsub("\n$", ""))
        end

        close(fds.stdin.write)
        close(fds.stdout.read)
        close(fds.stderr.read)

        os.exit(status)
      end

      return status, fds.stdout.read, fds.stderr.read
    end
  end
end

local semver = function(self)
  local v = self.version:gmatch("[^.%s]+")
  return v(), v(), v()
end

local do_table = function(task)
  chdir(S)

  MSG(string.format("\27[0;33m%s/%s\27[0m %s \27\27[0m",
    task.pkg.name, task.pkg.version, task.action, remote))

  for k, v in pairs(task.arg or {}) do
    local status, pstdout, pstderr = run(v, task)
    if status ~= 0 then return status end
  end
end

local do_package = function(task)
  MSG(string.format("\27[0;33m%s/%s\27[0m package\27[0m",
    task.pkg.name, task.pkg.version))

  install(lfs.pkg, "0755")
  local status, pstdout, pstderr = run(string.format("tar cJpf %s/%s-%s.tar.xz -C %s .",
    lfs.pkg, task.pkg.name, task.pkg.version, D), task)
  return status
end

local git_checkout = function(task)
  local remote = task.arg.remote:gsub("(.*[/:])(.*)", "%2")
  local gitdir = string.format("%s/git/%s", lfs.downloads, task.arg.remote:gsub("[:@/]", "_"))
  local S = string.format("%s/%s/%s", lfs.build, task.pkg.name, remote:gsub(".git$", ""))

  MSG(string.format("\27[0;33m%s/%s\27[0m unpack \27[0;34m%s -> %s\27[0m",
    task.pkg.name, task.pkg.version, remote, task.arg.rev))

  install(S, "0755")
  local status, pstdout, pstderr = run(string.format("git --git-dir=%s --work-tree=%s checkout %s -f",
    gitdir, S, task.arg.rev), task)
  return status
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
    cmd = string.format("git clone --quiet --bare --mirror %s %s", task.arg.remote, gitdir)
  end

  local status, pstdout, pstderr = run(cmd, task)
  return status
end

local add_task = function(tasks, name, action, task)
  local key = string.format("%s:%s", name, action)
  tasks[key] = tasks[key] or {}
  task.action = action
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

  W = string.format("%s/%s", lfs.build, target)
  S = string.format("%s/%s", W, target)
  D = string.format("%s/image", W)
  L = string.format("%s/logs", W)

  cc = {
    build = lfs.cc.amd64,
    host = lfs.cc.amd64,
    target = lfs.cc.amd64
  }
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
      add_task(tasks, fenv.pkg.name, "fetch", { pkg = fenv.pkg, task = git_clone, arg = v, fenv = fenv })
      DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mgit_checkout %s -> %s\27[0m",
        fenv.pkg.name, fenv.pkg.version, v.remote:gsub("(.*[/:])(.*)", "%2"), v.rev))
      local after = string.format("%s:fetch", fenv.pkg.name)
      add_task(tasks, fenv.pkg.name, "unpack", { pkg = fenv.pkg, task = git_checkout, arg = v, fenv = fenv, after = { after } })
    end
  end

  if type(fenv.pkg.prepare) == "table" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mprepare\27[0m", fenv.pkg.name, fenv.pkg.version))
    local after = string.format("%s:unpack", fenv.pkg.name)
    add_task(tasks, fenv.pkg.name, "prepare", { pkg = fenv.pkg, task = do_table, arg = fenv.pkg.prepare, fenv = fenv, after = { after } })
  end

  if type(fenv.pkg.build) == "table" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mbuild\27[0m", fenv.pkg.name, fenv.pkg.version))
    local after = string.format("%s:prepare", fenv.pkg.name)
    add_task(tasks, fenv.pkg.name, "build", { pkg = fenv.pkg, task = do_table, arg = fenv.pkg.build, fenv = fenv, after = { after } })
  end

  if type(fenv.pkg.install) == "table" then
    DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34minstall\27[0m", fenv.pkg.name, fenv.pkg.version))
    local after = string.format("%s:build", fenv.pkg.name)
    add_task(tasks, fenv.pkg.name, "install", { pkg = fenv.pkg, task = do_table, arg = fenv.pkg.install, fenv = fenv, after = { after } })
  end

  DEBUG(string.format("\27[0;33m%s/%s\27[0m add task \27[0;34mpackage\27[0m", fenv.pkg.name, fenv.pkg.version))
  local after = string.format("%s:install", fenv.pkg.name)
  add_task(tasks, fenv.pkg.name, "package", { pkg = fenv.pkg, task = do_package, arg = fenv.pkg.split, fenv = fenv, after = { after } })

  return tasks
end

function main()
  setloglvl(20)

  local conf = string.format("%s/conf/construir.lua", lfs.root)
  local enoent = { type = "-" }
  if (stat(conf) or enoent)["type"] == "f" then
    dofile(conf)
  end

  lfs.recipes = lfs.recipes or string.format("%s/recipes", lfs.root)
  lfs.downloads = lfs.downloads or string.format("%s/dl", lfs.root)
  lfs.build = lfs.build or string.format("%s/build", lfs.root)
  lfs.pkg = lfs.pkg or string.format("%s/pkg", lfs.root)

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

  nftw(lfs.build, remove, 10, FTW_DEPTH | FTW_PHYS)
  while amount(tasks) > 0 do
    for k, queue in pairs(tasks or {}) do
      for i, v in pairs(queue or {}) do
        local ack = true
        for _, dep in pairs(v.after or {}) do
          if tasks[dep] then ack = false end
        end
        if ack then
          _ENV = v.fenv
          install(L, "0755")
          v.task(v)
          _ENV = _G
          tasks[k][i] = nil
          if amount(tasks[k]) == 0 then tasks[k] = nil end
        end
      end
    end
  end
end
