-- Launcher: open the NemoClaw chat dashboard on the DGX Spark.
-- Runs the connect script in Terminal.app explicitly, so it never depends on
-- whatever your default terminal is (e.g. a broken Ghostty). Double-click the
-- built .app; macOS launches it directly (not through any terminal).
tell application "Terminal"
	activate
	do script "bash \"$HOME/nemoclaw-connect.sh\""
end tell
