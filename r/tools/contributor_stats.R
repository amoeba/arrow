# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Contributor statistics for release announcements.
#
# Usage: launch R from the root of the arrow git repo, then:
#
#   source("r/tools/contributor_stats.R")
#   release_contributor_stats("apache-arrow-25.0.0", "apache-arrow-26.0.0")
#
# or, for just the list of first-time contributors to a subdirectory:
#
#   print_new_contributors("apache-arrow-25.0.0", "apache-arrow-26.0.0", "r")
#
# To see who was counted and under which identities:
#
#   contributor_table("apache-arrow-25.0.0", "apache-arrow-26.0.0")
#
# Compare release tags of the same kind (X.0.0 to Y.0.0) for
# release-over-release stats.
#
# How contributors are counted:
#
# - A commit's contributors are its git author plus anyone named in its
#   Authored-by, Lead-authored-by, or Co-authored-by trailers (written by
#   dev/merge_arrow_pr.py and by GitHub). Signed-off-by names the committer
#   who merged the PR, so it is ignored.
# - Identities ("Name <email>") are grouped into one person when they share an
#   email address, a GitHub user (from users.noreply.github.com addresses), or
#   a normalized multi-word name. Single-word names are never matched on name
#   alone. `contributor_aliases` below links identities that can't be matched
#   automatically.
# - Bots and AI assistants (see `bot_patterns`) are dropped.
# - Commits in the range that were already cherry-picked into `ref_from` are
#   not counted again.
# - "Touched cpp/" or "touched r/" means the commit changed files under that
#   directory. Release housekeeping commits ("MINOR: [Release] ...") are
#   excluded from those per-directory counts but still count towards `total`.

# Pairs of author names that refer to the same person but share no email,
# GitHub user, or name with each other, e.g. c("old name" = "Full Name").
# Names are matched exactly.
contributor_aliases <- character()

# Identities matching any of these (case-insensitive, against "Name <email>")
# are bots or AI assistants rather than contributors.
bot_patterns <- c(
  "\\[bot\\]",
  "^copilot\\b",
  "<copilot@github\\.com>",
  "\\+copilot@users\\.noreply\\.github\\.com>",
  "<noreply@anthropic\\.com>",
  "<no-reply@databricks\\.com>",
  "^isaac$"
)

release_commit_pattern <- "^MINOR: \\[Release\\]"

# Run a git command, erroring if it fails. Returns stdout as a character vector.
git <- function(...) {
  out <- suppressWarnings(system2("git", shQuote(c(...)), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("git ", paste(c(...), collapse = " "), " failed:\n", paste(out, collapse = "\n"))
  }
  enc2utf8(as.character(out))
}

stopifnotinrepo <- function() {
  git("rev-parse", "--is-inside-work-tree")
  invisible(TRUE)
}

stopifnotref <- function(ref) {
  stopifnot(is.character(ref), length(ref) == 1, nchar(ref) > 0)
  status <- system2(
    "git",
    c("rev-parse", "--verify", "--quiet", paste0(ref, "^{commit}")),
    stdout = FALSE,
    stderr = FALSE
  )
  if (status != 0) {
    stop(
      "'",
      ref,
      "' is not a git ref in this repo. Release tags look like ",
      "'apache-arrow-",
      sub("^apache-arrow-", "", ref),
      "'."
    )
  }
  invisible(TRUE)
}

# Parse commits into a data frame with one row per (commit, identity).
# Columns: hash, subject, identity ("Name <email>").
read_commit_identities <- function(...) {
  sep <- "\x1f"
  lines <- git(
    "log",
    "--format=tformat:%H%x1f%s%x1f%an <%ae>%x1f%(trailers:only,unfold,separator=%x1f)",
    ...
  )
  lines <- lines[nzchar(lines)]
  fields <- strsplit(lines, sep, fixed = TRUE)
  hash <- vapply(fields, `[`, "", 1)
  subject <- vapply(fields, `[`, "", 2)
  # Everything from the third field on: the git author, then trailers
  rest <- lapply(fields, `[`, -(1:2))
  df <- data.frame(
    hash = rep(hash, lengths(rest)),
    subject = rep(subject, lengths(rest)),
    pos = unlist(lapply(lengths(rest), seq_len)),
    value = trimws(unlist(rest))
  )
  is_author <- df$pos == 1
  is_author_trailer <- grepl("^(lead-authored-by|authored-by|co-authored-by):", df$value, ignore.case = TRUE)
  df <- df[is_author | is_author_trailer, ]
  df$identity <- ifelse(df$pos == 1, df$value, trimws(sub("^[^:]+:", "", df$value)))
  df$role <- ifelse(df$pos == 1, "author", tolower(sub(":.*$", "", df$value)))
  df <- df[nzchar(df$identity), c("hash", "subject", "identity", "role")]
  df <- df[!duplicated(df[c("hash", "identity")]), ]
  rownames(df) <- NULL
  df
}

identity_name <- function(identity) {
  trimws(sub("\\s*<[^>]*>\\s*$", "", identity))
}

identity_email <- function(identity) {
  email <- ifelse(grepl("<[^>]*>\\s*$", identity), sub("^.*<([^>]*)>\\s*$", "\\1", identity), "")
  tolower(trimws(email))
}

normalize_name <- function(name) {
  x <- iconv(name, "UTF-8", "ASCII//TRANSLIT", sub = "")
  x <- tolower(x)
  x <- gsub("[._-]+", " ", x)
  x <- gsub("[^a-z ]", "", x)
  gsub("\\s+", " ", trimws(x))
}

is_bot <- function(identity) {
  Reduce(`|`, lapply(bot_patterns, grepl, x = identity, ignore.case = TRUE, perl = TRUE))
}

# Group identities into people. `identity_df` is the output of
# read_commit_identities(). Returns a named integer vector mapping each
# identity to a person id.
group_identities <- function(identity_df) {
  identities <- unique(identity_df$identity)
  n <- length(identities)
  parent <- seq_len(n)
  find <- function(i) {
    while (parent[i] != i) {
      parent[i] <<- parent[parent[i]]
      i <- parent[i]
    }
    i
  }
  union <- function(members) {
    if (length(members) < 2) {
      return()
    }
    roots <- vapply(members, find, integer(1))
    parent[roots] <<- roots[1]
  }

  names <- identity_name(identities)
  emails <- identity_email(identities)
  norm <- normalize_name(names)

  # GitHub noreply addresses: "<id>+<login>@users.noreply.github.com" or
  # "<login>@users.noreply.github.com"
  noreply <- sub("@users\\.noreply\\.github\\.com$", "", emails)
  is_noreply <- noreply != emails
  gh_login <- ifelse(is_noreply, sub("^[0-9]+\\+", "", noreply), "")

  # A one-word name that looks like a GitHub login (e.g. "dkp116") is matched
  # against the logins in noreply addresses.
  # Only logins that actually appear in a noreply address are used, so two
  # people who share a one-word name aren't matched with each other.
  name_as_login <- ifelse(grepl("^[A-Za-z0-9-]+$", names), tolower(names), "")
  name_as_login[!name_as_login %in% gh_login] <- ""

  keys <- list(
    email = ifelse(nzchar(emails), paste0("email:", emails), NA),
    login = ifelse(nzchar(gh_login), paste0("login:", gh_login), NA),
    name_login = ifelse(nzchar(name_as_login), paste0("login:", name_as_login), NA),
    name = ifelse(grepl(" ", norm), paste0("name:", norm), NA)
  )

  alias_canonical <- unname(contributor_aliases[names])
  alias_key <- ifelse(is.na(alias_canonical), NA, paste0("alias:", alias_canonical))
  alias_key[names %in% contributor_aliases] <- paste0("alias:", names[names %in% contributor_aliases])
  keys$alias <- alias_key

  key_idx <- rep(seq_len(n), length(keys))
  key_val <- unlist(keys, use.names = FALSE)
  keep <- !is.na(key_val)
  for (members in split(key_idx[keep], key_val[keep])) union(members)

  # The same name appearing twice on one commit (e.g. a co-author listed under
  # two emails) is one person, even for one-word names.
  row_idx <- match(identity_df$identity, identities)
  row_norm <- normalize_name(identity_name(identity_df$identity))
  has_norm <- nzchar(row_norm)
  same_commit <- split(row_idx[has_norm], paste(identity_df$hash[has_norm], row_norm[has_norm]))
  for (members in same_commit) union(unique(members))

  # dev/merge_arrow_pr.py squash-merges through the GitHub API, so the git
  # author is the GitHub account that opened the PR. When the PR has a single
  # author (an Authored-by trailer and no Co-authored-by), the trailer is
  # usually that same person under their local git identity. It isn't always:
  # someone can open a PR containing another person's commits. So only link a
  # trailer-only person (never a git author themselves) and only when every
  # such commit points at the same PR opener. Lead-authored-by is chosen by the
  # merger, so it isn't used here.
  roots <- vapply(seq_len(n), find, integer(1))
  row_root <- roots[row_idx]
  author_roots <- unique(row_root[identity_df$role == "author"])
  is_sole <- ave(
    identity_df$role,
    identity_df$hash,
    FUN = function(r) sum(r == "authored-by") == 1 && all(r %in% c("author", "authored-by"))
  ) == "TRUE"
  sole_df <- data.frame(hash = identity_df$hash, role = identity_df$role, root = row_root)[is_sole, ]
  opener <- sole_df$root[sole_df$role == "author"][match(sole_df$hash, sole_df$hash[sole_df$role == "author"])]
  cand <- sole_df[sole_df$role == "authored-by", ]
  cand$opener <- opener[sole_df$role == "authored-by"]
  cand <- cand[cand$root != cand$opener & !cand$root %in% author_roots, ]
  openers <- lapply(split(cand$opener, cand$root), unique)
  for (r in names(openers)[lengths(openers) == 1]) {
    union(c(as.integer(r), openers[[r]]))
  }

  roots <- vapply(seq_len(n), find, integer(1))
  setNames(match(roots, unique(roots)), identities)
}

# Pick a display name for each person: prefer full names (containing a space
# and no "@"), then the most used, then the longest.
display_names <- function(identity_df, person) {
  df <- data.frame(person = person[identity_df$identity], name = identity_name(identity_df$identity))
  counts <- aggregate(list(n = df$name), df, length)
  full <- grepl(" ", counts$name) & !grepl("@", counts$name)
  counts <- counts[order(counts$person, !full, -counts$n, -nchar(counts$name)), ]
  counts[!duplicated(counts$person), c("person", "name")]
}

# Hashes of commits in ref_from..ref_to, excluding ones whose patch already
# landed in ref_from via a cherry-pick.
range_commits <- function(ref_from, ref_to) {
  git("rev-list", "--cherry-pick", "--right-only", paste0(ref_from, "...", ref_to))
}

# Hashes of non-release commits reachable from `refs` that touched `path`
commits_touching <- function(refs, path) {
  out <- git("log", "--format=tformat:%H%x1f%s", refs, "--", path)
  parts <- do.call(rbind, strsplit(out, "\x1f", fixed = TRUE))
  parts[!grepl(release_commit_pattern, parts[, 2]), 1]
}

# One row per contributor to ref_from..ref_to, with whether they touched cpp/
# and r/, whether they're new to the project (`new`), and whether this is their
# first contribution touching `subdirectory` (`first_in_subdirectory`).
contributor_table <- function(ref_from, ref_to, subdirectory = "r") {
  stopifnotinrepo()
  stopifnotref(ref_from)
  stopifnotref(ref_to)
  stopifnot(file.exists(subdirectory))

  # Read every commit, not just those up to ref_to, so that identities linked
  # by later commits are still grouped. Counting below only uses commits in
  # the range (or reachable from ref_from, for "new" checks).
  all <- read_commit_identities("--all")
  range_hashes <- range_commits(ref_from, ref_to)
  all <- all[!is_bot(all$identity), ]
  person <- group_identities(all)
  all$person <- person[all$identity]

  in_range <- all$hash %in% range_hashes
  prior <- all$hash %in% git("rev-list", ref_from)

  range_spec <- paste0(ref_from, "..", ref_to)
  cpp_hashes <- commits_touching(range_spec, "cpp")
  r_hashes <- commits_touching(range_spec, "r")
  subdir_hashes <- commits_touching(range_spec, subdirectory)
  prior_subdir_hashes <- commits_touching(ref_from, subdirectory)

  range_df <- all[in_range, ]
  people <- sort(unique(range_df$person))

  out <- data.frame(
    person = people,
    n_commits = as.integer(table(factor(range_df$person, people))[as.character(people)]),
    cpp = people %in% range_df$person[range_df$hash %in% cpp_hashes],
    r = people %in% range_df$person[range_df$hash %in% r_hashes],
    new = !people %in% all$person[prior],
    first_in_subdirectory = people %in% range_df$person[range_df$hash %in% subdir_hashes] &
      !people %in% all$person[all$hash %in% prior_subdir_hashes]
  )
  dn <- display_names(all, person)
  out$name <- dn$name[match(out$person, dn$person)]
  out$aliases <- vapply(out$person, function(p) {
    paste(sort(unique(range_df$identity[range_df$person == p])), collapse = "; ")
  }, character(1))
  out <- out[order(tolower(out$name)), c("name", "n_commits", "cpp", "r", "new", "first_in_subdirectory", "aliases")]
  rownames(out) <- NULL
  out
}

# Contributors to `subdirectory` between `ref_from` and `ref_to` whose first
# contribution touching `subdirectory` is in that range. With the default
# subdirectory, these are first-time contributors to the project.
print_new_contributors <- function(ref_from, ref_to, subdirectory = ".") {
  tbl <- contributor_table(ref_from, ref_to, subdirectory)
  if (subdirectory == ".") tbl$name[tbl$new] else tbl$name[tbl$first_in_subdirectory]
}

# Summary stats for the release announcement: total contributors, how many
# touched only C++, only R, or both, first-time contributors to the project,
# and contributors whose first change touching r/ is in this release.
release_contributor_stats <- function(ref_from, ref_to) {
  tbl <- contributor_table(ref_from, ref_to, "r")
  list(
    total = nrow(tbl),
    cpp_only = sum(tbl$cpp & !tbl$r),
    r_only = sum(tbl$r & !tbl$cpp),
    both = sum(tbl$cpp & tbl$r),
    first_timers = tbl$name[tbl$new],
    first_timers_r = tbl$name[tbl$first_in_subdirectory]
  )
}
