defmodule FeedPug.Groups.NotOwnerError do
  @moduledoc "Raised when a user attempts to mutate a group they do not own."
  defexception message: "not the owner of this group"
end
