defmodule Isomer.Paths do
  @moduledoc """
  Confine corpus filesystem access to a root directory.

  Mix tooling joins repo-relative paths for YAML/Markdown. Even when those
  fragments are normally constants, CLI args and YAML fields (framework ids,
  schema filenames) must not escape the root via `..` or absolute segments.
  """

  @segment_re ~r/\A[A-Za-z0-9][A-Za-z0-9._+-]*\z/
  @schema_re ~r/\A[a-z0-9][a-z0-9._-]*\.schema\.json\z/
  @glob_meta_re ~r/[\*\?\[]/

  @doc "Absolute, expanded corpus root."
  def expand_root!(root) when is_binary(root), do: Path.expand(root)

  @doc """
  Join `relative` under `root`, rejecting traversal.

  `relative` must be a relative path (no leading `/`) and must not escape
  `root` after `.` / `..` normalization (`Path.safe_relative/2`).
  """
  def join!(root, relative) when is_binary(root) and is_binary(relative) do
    root = expand_root!(root)
    rel = assert_safe_relative!(relative, root)
    Path.expand(rel, root)
  end

  def join!(root, parts) when is_binary(root) and is_list(parts) do
    join!(root, Path.join(Enum.map(parts, &to_string/1)))
  end

  @doc """
  Expand `path` relative to `root` and require the result to stay under `root`.

  Used for CLI paths (delta mapping file, ingest sample, …).
  """
  def expand_under!(root, path) when is_binary(root) and is_binary(path) do
    root = expand_root!(root)
    abs = Path.expand(path, root)
    assert_under_root!(abs, root)
  end

  @doc "True when `path` expands to `root` or a descendant."
  def under_root?(path, root) when is_binary(path) and is_binary(root) do
    root = expand_root!(root)
    abs = Path.expand(path)
    abs == root or String.starts_with?(abs, root <> "/")
  end

  @doc "Raise unless `path` is under `root`; return the expanded absolute path."
  def assert_under_root!(path, root) when is_binary(path) and is_binary(root) do
    root = expand_root!(root)
    abs = Path.expand(path)

    if under_root?(abs, root) do
      abs
    else
      raise ArgumentError, "path escapes corpus root #{inspect(root)}: #{inspect(path)}"
    end
  end

  @doc """
  Relative path of `path` under `root` for display / `source_path`.

  Requires `path` to stay under `root` (no traversal).
  """
  def relative!(path, root) when is_binary(path) and is_binary(root) do
    root = expand_root!(root)
    abs = assert_under_root!(path, root)

    case Path.safe_relative(Path.relative_to(abs, root), root) do
      {:ok, rel} ->
        rel

      :error ->
        raise ArgumentError, "path escapes corpus root #{inspect(root)}: #{inspect(path)}"
    end
  end

  @doc """
  Wildcard under `root` for a **relative** glob (may contain `*` / `?`).

  Rejects absolute globs and `..` segments. Results outside `root` are dropped.
  """
  def wildcard!(root, relative_glob) when is_binary(root) and is_binary(relative_glob) do
    root = expand_root!(root)
    assert_safe_glob!(relative_glob)
    pattern = Path.join(root, relative_glob)

    pattern
    |> Path.wildcard()
    |> Enum.filter(&under_root?(&1, root))
    |> Enum.sort()
  end

  @doc "Single path segment (framework id, version, schema basename, …)."
  def segment!(name) when is_binary(name) do
    if Regex.match?(@segment_re, name) do
      name
    else
      raise ArgumentError,
            "unsafe path segment #{inspect(name)} (must be alphanumeric with ._+- only)"
    end
  end

  @doc "Basename for `schemas/*.schema.json`."
  def schema_name!(name) when is_binary(name) do
    if Regex.match?(@schema_re, name) do
      name
    else
      raise ArgumentError, "unsafe schema name #{inspect(name)}"
    end
  end

  defp assert_safe_relative!(relative, root) do
    if Path.type(relative) == :absolute do
      raise ArgumentError, "absolute path not allowed under corpus root: #{inspect(relative)}"
    end

    if String.contains?(relative, "\\") or String.contains?(relative, "\0") do
      raise ArgumentError, "unsafe path characters in #{inspect(relative)}"
    end

    case Path.safe_relative(relative, root) do
      {:ok, rel} ->
        rel

      :error ->
        raise ArgumentError, "path escapes corpus root: #{inspect(relative)}"
    end
  end

  defp assert_safe_glob!(glob) do
    if Path.type(glob) == :absolute do
      raise ArgumentError, "absolute glob not allowed: #{inspect(glob)}"
    end

    if String.contains?(glob, "\\") or String.contains?(glob, "\0") do
      raise ArgumentError, "unsafe glob characters in #{inspect(glob)}"
    end

    glob
    |> Path.split()
    |> Enum.each(fn segment ->
      cond do
        segment in [".", ""] ->
          :ok

        segment == ".." ->
          raise ArgumentError, "glob must not contain '..': #{inspect(glob)}"

        Regex.match?(@glob_meta_re, segment) ->
          # Wildcard segment — still reject embedded '..' text.
          if String.contains?(segment, "..") do
            raise ArgumentError, "unsafe glob segment #{inspect(segment)}"
          end

        true ->
          _ = segment!(segment)
      end
    end)

    :ok
  end
end
