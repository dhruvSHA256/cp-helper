local lunajson = require'lunajson'
local path = require'path'
local opts = vim.g['cph']
local port = opts['port'] or 1327

function exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok then
        if code == 13 then
            -- Permission denied, but it exists
            return true
        end
    end
    return ok, err
end
--- Check if a directory exists in this path
function isdir(path)
    -- "/" works on both Unix and Windows
    return exists(path .. '/')
end

function mkdir(dirname) os.execute('mkdir ' .. dirname) end
local M = {}

function M.open_submit_page()
    local problem = vim.t.problem
    local url
    if problem.platform == 'codeforce' then
        url = problem.url:gsub('problem/.*', 'submit')
    elseif problem.platform == 'codechef' then
        -- url = problem.url:gsub('www.codechef.com/.*/problems', 'www.codechef.com/submit')
        -- codechef uses codechef.com/<contest>/submit/<problem_name> for active
        -- contests and codechef.com/submit/<problem_name> for old problems
        url = problem.url:gsub('problems', 'submit')
    else
        print('No predefined submit url for this platform: ' .. problem.platform)
        return
    end
    vim.cmd[[normal ggyG]]
    print('Solution copied to clip')
    os.execute('xdg-open "' .. url .. '"')
end

function M.open_problem_page()
    local problem = vim.t.problem
    os.execute('xdg-open "' .. problem.url .. '"')
end

-- saves problem json in .local/cp_helper/problem_name.json
local function save_problem(response)

    -- get json from whole response
    local t = {}
    for x in response:gmatch('[^\r\n]+') do table.insert(t, x) end
    -- get body of response from table
    local json_string = t[#t]

    -- convert json to a table
    local problem = lunajson.decode(json_string)
    -- local problem_name = problem['name']:gsub('%s', '_'):gsub('%.', ''):gsub("(['*$\\#-])", "\\%1"):lower()
    local problem_name = problem['name']:gsub('%s', '_'):gsub('%.', ''):gsub('([\'*$\\#-])', '')
                           :lower()
    print(problem_name)

    -- get the platform of problem
    if problem.url:find('codeforce') then
        problem.platform = 'codeforce'
    elseif problem.url:find('codechef') then
        problem.platform = 'codechef'
    else
        problem.platform = 'misc'
    end

    -- prob_dir (~/.local/cp_helper.vim/problem_name) stores problems with tests and json
    local prob_dir = path.join(opts.dir, problem_name)
    -- sol_dir (~/vault/cp) stores the sol_file.cpp
    local sol_dir = path.join(opts.sol_dir, problem.platform)
    -- if directory does not exist ; make it
    if not isdir(prob_dir) then mkdir(prob_dir) end
    if not isdir(sol_dir) then mkdir(sol_dir) end

    for x, test in ipairs(problem.tests) do
        sampleip = path.join(prob_dir, problem_name .. '.' .. tostring(x) .. '.in')
        sampleop = path.join(prob_dir, problem_name .. '.' .. tostring(x) .. '.sol')
        io.open(sampleip, 'w+'):write(test.input)
        io.open(sampleop, 'w+'):write(test.output)
    end

    local solution = path.join(sol_dir, problem_name .. '.' .. opts.sol_lang)
    problem.solution = solution

    -- saves platform additional to existing data in json file
    local prob_json_file = path.join(prob_dir, problem_name .. '.json')
    local json_handler = io.open(prob_json_file, 'w+')
    json_handler:write(lunajson.encode(problem))
    json_handler:close()

    -- link ot _latest_
    os.execute('ln -sf ' .. prob_json_file .. ' ' .. path.join(opts.dir, '_latest_'))

    print('Got ' .. problem_name)

end

local server_running = false
local server_port = 0
M.run_server = function()

    local function create_server(host, port, on_connect)
        local server = vim.loop.new_tcp()
        server:bind(host, port)
        server:listen(128, function(err)
            assert(not err, err) -- Check for errors.
            local sock = vim.loop.new_tcp()

            if not sock then print('Error') end

            server:accept(sock) -- Accept client connection.
            on_connect(sock) -- Start reading messages.
        end)
        return server
    end

    if server_running == false then
        local server = create_server('0.0.0.0', port, function(sock)
            sock:read_start(function(err, chunk)
                assert(not err, err) -- Check for errors.
                if chunk then
                    save_problem(chunk)
                else -- EOF (stream closed).
                    sock:close() -- Always close handles to avoid leaks.
                end
            end)
        end)

        if not server then
            print('Error starting server')
            return
        end

        server_port = server:getsockname().port
        print('Started cph server on port: ' .. server_port)
        server_running = true
    else
        print('Cph server already running on port: ' .. server_port)
        -- print('Cph server already running')
    end

end

M.open_problem = function(problem_name)

    local prob_json, problem

    -- if no args give open latest problem
    if not problem_name then

        prob_json = assert(io.open(path.join(opts.dir, '_latest_')), 'Couldnt open _latest_')
        problem = lunajson.decode(prob_json:read('*a'))
        problem_name = problem.name:gsub('%s', '_'):gsub('%.', ''):gsub('([\'*$\\#-])', ''):lower()
        prob_json:close()

    else
        -- if problem_name.json doesnt exists return
        if not exists(path.join(opts.dir, problem_name, problem_name .. '.json')) then
            print('No such file : ' .. path.join(opts.dir, problem_name .. '.json'))
            return
        end
        prob_json = assert(io.open(path.join(opts.dir, problem_name, problem_name .. '.json')),
                           'Couldnt open ' .. problem_name .. '.json')
        problem = lunajson.decode(prob_json:read('*a'))
        prob_json:close()
    end

    -- copy template to sol_dir/platform/sol_file and writes problem link and date in it
    if not exists(problem.solution) then
        os.execute('cp ' .. opts.template .. ' ' .. problem.solution)
        os.execute('sed -e "s/Problem link :/Problem link : ' .. problem.url:gsub('/', '\\/') ..
                     ' /g"' .. ' -e "s/Date.*:/Date         : ' .. os.date('%b-%d-%Y') .. '/g" ' ..
                     ' -e "s/IO(\\"PNAME\\");/IO(\\"' .. problem_name .. '\\");/g" ' ..
                     opts.template .. ' > ' .. problem.solution)
    end

    if vim.fn.expand('%:p') ~= tostring(problem.solution) then
        if vim.fn.getwinvar(w, '&ft') ~= 'startify' then vim.cmd('tabnew') end
        vim.cmd('edit ' .. problem.solution)
    end
    vim.cmd('lcd %:p:h')
    vim.api.nvim_tabpage_set_var(0, 'problem', {
        ['name'] = problem_name,
        ['url'] = problem.url,
        ['platform'] = problem.platform,
        -- ['tests'] = problem.tests,
        -- ['solution'] = problem.solution,
        -- ['executable'] = path.join(opts.sol_dir, problem.platform, problem_name),
    })

end

local result_wins = {}
local result_bufs = {}
M.show_result = function(problem_name, result)

    local result_win = result_wins[problem_name]

    if result_win and vim.api.nvim_win_is_valid(result_win) then

        vim.api.nvim_set_current_win(result_win)

    else

        vim.api.nvim_command('topleft 50vnew')
        result_win = vim.api.nvim_get_current_win()
        result_wins_opts = {
            ['wrap'] = false,
            ['cursorline'] = true,
            ['rnu'] = false,
            ['nu'] = false,
        }
        vim.api.nvim_win_set_option(result_win, 'wrap', false)
        vim.api.nvim_win_set_option(result_win, 'cursorline', true)
        vim.api.nvim_win_set_option(result_win, 'rnu', false)
        vim.api.nvim_win_set_option(result_win, 'nu', false)
        result_wins[problem_name] = result_win

    end

    local result_buf = result_bufs[problem_name]

    if not result_buf or not vim.api.nvim_buf_is_valid(result_buf) then
        result_buf = vim.api.nvim_get_current_buf()
        result_bufs[problem_name] = result_buf
        vim.api.nvim_buf_set_option(result_buf, 'buftype', 'nofile')
        vim.api.nvim_buf_set_option(result_buf, 'buflisted', false)
        vim.api.nvim_buf_set_option(result_buf, 'swapfile', false)
        vim.api.nvim_buf_set_option(result_buf, 'bufhidden', 'wipe')
        vim.api.nvim_buf_set_option(result_buf, 'filetype', 'nvim-oldfile')
        vim.api.nvim_buf_set_keymap(result_buf, 'n', 'q', ':q!<CR>',
                                    {nowait = true, noremap = true, silent = true})
    end

    vim.api.nvim_buf_set_option(result_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, result)
    vim.api.nvim_buf_set_option(result_buf, 'modifiable', false)
    vim.api.nvim_set_current_buf(result_buf)

end

M.run_test = function()

    local strip = function(str) return str:gsub('^%s*(.-)%s*$', '%1') end

    local result = {}
    local problem = assert(vim.api.nvim_tabpage_get_var(0, 'problem'), 'No problem in current tab')
    local tests_dir = path.join(opts.dir, problem.name)
    local executable = path.join(opts.sol_dir, problem.platform, problem.name)
    if not exists(executable) then
        print('No executable (' .. executable .. '), Compile executable first')
        return
    end
    local t = 0
    for input in io.popen('ls ' .. tests_dir .. '/' .. problem.name .. '*.in'):read('*a'):gmatch(
                   '[^\r\n]+') do
        t = t + 1

        local sol = tests_dir .. '/' .. problem.name .. '.' .. t .. '.sol'
        local out = tests_dir .. '/' .. problem.name .. '.' .. t .. '.out'
        local err = tests_dir .. '/' .. problem.name .. '.' .. t .. '.err'

        -- TODO: Use vim.loop
        local pstream = assert(io.popen(string.format(
                                          '/usr/bin/timeout %s %s > %s <%s 2> %s ; echo $?',
                                          opts.timeout, executable, out, input, err)))

        local return_code = pstream:read('*a'):gsub('^%s*(.-)%s*$', '%1')
        pstream:close()

        local ipcontent = strip(io.open(input):read('*a'))
        local errcontent = strip(io.open(err):read('*a'))

        table.insert(result, #result + 1, '--- TEST ' .. t .. ' ---')
        if return_code == tostring(124) then

            table.insert(result, #result + 1, 'TLE')
            table.insert(result, #result + 1, ' ')

        elseif return_code == tostring(0) then

            local outcontent = strip(io.open(out):read('*a'))

            if exists(sol) then
                solcontent = strip(io.open(sol):read('*a'))

                if solcontent == outcontent then
                    table.insert(result, #result + 1, 'PASS')
                    table.insert(result, #result + 1, ' ')
                else

                    table.insert(result, #result + 1, '::input::')
                    table.insert(result, #result + 1, ' ')
                    for line in ipcontent:gmatch('[^\r\n]+') do
                        table.insert(result, #result + 1, '' .. line)
                    end
                    table.insert(result, #result + 1, ' ')
                    table.insert(result, #result + 1, '::expected::')
                    table.insert(result, #result + 1, ' ')
                    for line in solcontent:gmatch('[^\r\n]+') do
                        table.insert(result, #result + 1, '' .. line)
                    end
                    table.insert(result, #result + 1, ' ')
                    table.insert(result, #result + 1, '::out::')
                    table.insert(result, #result + 1, ' ')
                    for line in outcontent:gmatch('[^\r\n]+') do
                        table.insert(result, #result + 1, '' .. line)
                    end
                    table.insert(result, #result + 1, ' ')

                end

            else

                table.insert(result, #result + 1, '::input::')
                table.insert(result, #result + 1, ' ')
                for line in ipcontent:gmatch('[^\r\n]+') do
                    table.insert(result, #result + 1, '' .. line)
                end
                table.insert(result, #result + 1, ' ')
                table.insert(result, #result + 1, '::out::')
                for line in outcontent:gmatch('[^\r\n]+') do
                    table.insert(result, #result + 1, '' .. line)
                end
                table.insert(result, #result + 1, ' ')
            end

            table.insert(result, #result + 1, '::stderr::')
            for line in errcontent:gmatch('[^\r\n]+') do
                table.insert(result, #result + 1, '' .. line)
            end
            table.insert(result, #result + 1, ' ')
        else

            table.insert(result, #result + 1, 'RUNTIME ERROR')
            table.insert(result, #result + 1, ' ')

        end

    end

    problem.total_test = t
    vim.api.nvim_tabpage_set_var(0, 'problem', problem)
    M.show_result(problem.name, result)
end

return M

