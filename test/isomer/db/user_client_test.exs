defmodule Isomer.Db.UserClientTest do
  use ExUnit.Case, async: true

  alias Isomer.Db.UserClient

  test "transient_error? recognizes connection and timeout kinds" do
    assert UserClient.transient_error?(%{kind: :connection, message: "could not connect"})
    assert UserClient.transient_error?(%{kind: :timeout, message: "RPC use timed out"})
    assert UserClient.transient_error?(%Mint.TransportError{reason: :timeout})

    assert UserClient.transient_error?(%{
             message: "could not connect: %Mint.TransportError{reason: :timeout}"
           })
  end

  test "transient_error? is false for auth failures" do
    refute UserClient.transient_error?(%{kind: :auth, message: "No record was returned"})
    refute UserClient.transient_error?(%{message: "Invalid email or password."})
  end
end
