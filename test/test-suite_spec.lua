local o = require("nvim-lsp-ts-utils.options")
local s = require("nvim-lsp-ts-utils.state")
local u = require("nvim-lsp-ts-utils.utils")
local ts_utils = require("nvim-lsp-ts-utils")
local import_all = require("nvim-lsp-ts-utils.import-all")
local watcher = require("nvim-lsp-ts-utils.watcher")

local pwd = vim.api.nvim_exec("pwd", true) .. "/"
local base_path = "test/files/"
local full_path = pwd .. base_path

local edit_test_file = function(name) vim.cmd("e " .. base_path .. name) end

local copy_test_file = function(original, target)
    u.file.cp(full_path .. original, full_path .. target)
end

local delete_test_file =
    function(target) u.file.rm(full_path .. target, true) end

local get_file_content = function()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("fix_current", function()
    after_each(function() vim.cmd("bufdo! bwipeout!") end)

    it("should import missing type", function()
        -- file declares an instance of User but does not import it from test-types.ts
        edit_test_file("fix-current.ts")
        vim.wait(1000)

        vim.lsp.diagnostic.goto_prev()
        ts_utils.fix_current()
        vim.wait(500)

        -- check that import statement has been added
        assert.equals(vim.fn.search("import { User }", "nw"), 1)
    end)
end)

describe("request-handlers", function()
    after_each(function()
        vim.cmd("bufdo! bwipeout!")
        o.set({enable_formatting = false})
    end)

    it("should apply eslint fix", function()
        -- file contains ==, which is a violation of eqeqeq
        edit_test_file("eslint-code-fix.js")
        vim.wait(500)
        vim.cmd("2")

        ts_utils.fix_current()
        vim.wait(500)

        -- check that eslint fix has been applied, replacing == with ===
        assert.equals(vim.fn.search("===", "nwp"), 1)
    end)

    it("should add disable rule comment with matching indentation", function()
        edit_test_file("eslint-code-fix.js")
        vim.wait(500)
        vim.cmd("2")

        ts_utils.fix_current(2)
        vim.wait(500)

        assert.equals(get_file_content()[2],
                      "  // eslint-disable-next-line eqeqeq")
    end)

    it("should show eslint diagnostics", function()
        edit_test_file("eslint-code-fix.js")
        ts_utils.diagnostics()
        vim.wait(500)
        assert.equals(vim.api.nvim_win_get_cursor(0)[1], 1)

        vim.lsp.diagnostic.goto_next()

        -- error is on line 2, so diagnostic.goto_next should move cursor down
        assert.equals(vim.api.nvim_win_get_cursor(0)[1], 2)
    end)

    it("should format file on buf.formatting_sync()", function()
        local formatted_line = [[import { User } from './test-types';]]
        o.set({enable_formatting = true})

        edit_test_file("format.ts")
        vim.wait(500)
        assert.is_not.equals(get_file_content()[1], formatted_line)

        vim.lsp.buf.formatting_sync()
        vim.wait(500)

        assert.equals(get_file_content()[1], formatted_line)
    end)

    it("should format file on buf.formatting()", function()
        local formatted_line = [[import { User } from './test-types';]]
        o.set({enable_formatting = true})

        -- file has bad spacing, no semicolon, and double quotes, all of which violate prettier rules
        edit_test_file("format.ts")
        vim.wait(500)
        assert.is_not.equals(get_file_content()[1], formatted_line)

        vim.lsp.buf.formatting()
        vim.wait(500)

        assert.equals(get_file_content()[1], formatted_line)
    end)

    it("should format non-tsserver file", function()
        local formatted_line = [[I have too many spaces]]
        o.set({enable_formatting = true})

        -- file has a bunch of extra spaces
        edit_test_file("format.md")
        vim.wait(500)
        assert.is_not.equals(get_file_content()[1], formatted_line)

        ts_utils.format()
        vim.wait(500)

        assert.equals(get_file_content()[1], formatted_line)
    end)
end)

describe("import_all", function()
    after_each(function() vim.cmd("bufdo! bwipeout!") end)

    it("should import both missing types (sync)", function()
        -- file contains 2 declarations for missing types
        edit_test_file("import-all.ts")
        vim.wait(1000)

        import_all(true)
        vim.wait(500)

        -- check that type import statements have been added and merged
        assert.equals(vim.fn.search("import { User, UserNotification }", "nw"),
                      1)
    end)

    it("should import both missing types (async)", function()
        edit_test_file("import-all.ts")
        vim.wait(1000)

        import_all()
        vim.wait(500)

        assert.equals(vim.fn.search("import { User, UserNotification }", "nw"),
                      1)
    end)
end)

describe("organize_imports", function()
    after_each(function() vim.cmd("bufdo! bwipeout!") end)

    it("should remove unused import (sync)", function()
        -- file imports both User and Notification but only uses User
        edit_test_file("organize-imports.ts")
        vim.wait(1000)

        ts_utils.organize_imports_sync()
        vim.wait(500)

        assert.equals(vim.fn.search("Notification", "nw"), 0)
        assert.equals(vim.fn.search("User", "nw"), 1)
    end)

    it("should remove unused import (async)", function()
        edit_test_file("organize-imports.ts")
        vim.wait(1000)

        ts_utils.organize_imports()
        vim.wait(500)

        assert.equals(vim.fn.search("Notification", "nw"), 0)
        assert.equals(vim.fn.search("User", "nw"), 1)
    end)
end)

local rename_file_setup = function()
    s.reset()

    copy_test_file("file-to-be-moved.orig.ts", "file-to-be-moved.ts")
    copy_test_file("linked-file.orig.ts", "linked-file.ts")
    copy_test_file("existing-file.orig.ts", "existing-file.ts")
end

local rename_file_breakdown = function()
    vim.cmd("bufdo! bwipeout!")
    watcher.stop()

    delete_test_file("new-path.ts")
    delete_test_file("linked-file.ts")
    delete_test_file("file-to-be-moved.ts")
    delete_test_file("existing-file.ts")
end

describe("rename_file", function()
    before_each(function() rename_file_setup() end)
    after_each(function() rename_file_breakdown() end)

    it("should throw error on invalid filetype", function()
        edit_test_file("invalid-file.txt")

        vim.wait(1000)

        assert.has_errors(function() ts_utils.rename_file() end)
    end)

    it("should move file to specified path", function()
        edit_test_file("file-to-be-moved.ts")
        local original_content = get_file_content()
        vim.wait(1000)

        local new_path = full_path .. "new-path.ts"
        ts_utils.rename_file(new_path)
        vim.wait(200)

        local new_content = get_file_content()
        assert.equals(vim.fn.bufname(vim.fn.bufnr()), new_path)
        assert.same(original_content, new_content)
    end)

    it("should overwrite existing file", function()
        edit_test_file("existing-file.ts")
        local original_content = get_file_content()

        edit_test_file("file-to-be-moved.ts")
        vim.wait(1000)
        local new_path = full_path .. "existing-file.ts"
        ts_utils.rename_file(new_path) -- prompt will be automatically accepted, it seems
        vim.wait(200)

        local new_content = get_file_content()
        assert.is.Not.same(original_content, new_content)
    end)

    it("should update imports in linked file on manual rename", function()
        edit_test_file("file-to-be-moved.ts")
        vim.wait(1000)

        local new_path = full_path .. "new-path.ts"
        ts_utils.rename_file(new_path)
        vim.wait(200)

        edit_test_file("linked-file.ts")
        assert.equals(vim.fn.search("new-path", "nw"), 1)
    end)

    it("should update imports in linked file on move", function()
        edit_test_file("file-to-be-moved.ts")
        watcher.start()
        vim.wait(1000)

        local new_path = full_path .. "new-path.ts"
        u.file.mv(full_path .. "file-to-be-moved.ts", new_path)
        vim.wait(200)

        edit_test_file("linked-file.ts")
        assert.equals(vim.fn.search("new-path", "nw"), 1)
    end)
end)

describe("edit_handler", function()
    before_each(function()
        copy_test_file("move-to-new-file.orig.ts", "move-to-new-file.ts")
    end)
    after_each(function()
        delete_test_file("move-to-new-file.ts")
        delete_test_file("functionToMove.ts")
    end)

    it("should fix range and make code action actually work", function()
        edit_test_file("move-to-new-file.ts")
        vim.wait(1000)
        vim.api.nvim_win_set_cursor(0, {3, 10})

        ts_utils.fix_current()
        vim.wait(500)

        assert.equals(u.file.exists(full_path .. "functionToMove.ts"), true)
        assert.equals(get_file_content()[1],
                      [[import { functionToMove } from "./functionToMove";]])

        edit_test_file("functionToMove.ts")
        assert.equals(get_file_content()[3],
                      "export function functionToMove() {")
    end)
end)
