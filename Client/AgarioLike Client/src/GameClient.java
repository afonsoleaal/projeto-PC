import java.io.*;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ConcurrentHashMap;

public class GameClient {
    private Socket socket;
    private DataOutputStream out;
    private DataInputStream in;
    private GameApp app;



    public GameClient(GameApp app) {
        this.app = app;
    }

    public void connect(String host, int port) {
        try {
            socket = new Socket(host, port);
            socket.setTcpNoDelay(true);
            out = new DataOutputStream(socket.getOutputStream());
            in = new DataInputStream(socket.getInputStream());

            new Thread(this::listenFromServer).start();
            System.out.println("Connected to Erlang server!");
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void sendAuthAction(int actionId, String username, String password) {
        try {
            byte[] userBytes = username.getBytes(StandardCharsets.UTF_8);
            byte[] passBytes = password.getBytes(StandardCharsets.UTF_8);

            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            DataOutputStream dos = new DataOutputStream(baos);

            dos.writeByte(actionId);
            dos.writeShort(userBytes.length);
            dos.write(userBytes);
            dos.writeShort(passBytes.length);
            dos.write(passBytes);

            out.write(baos.toByteArray());
            out.flush();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void sendMovement(int left, int right, int forward) {
        try {
            out.writeByte(4);
            out.writeByte(left);
            out.writeByte(right);
            out.writeByte(forward);
            out.flush();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void listenFromServer() {
        try {
            while (true) {
                byte packetId = in.readByte();

                if (packetId == 16) {
                    byte status = in.readByte();
                    short msgLen = in.readShort();
                    byte[] msgBytes = new byte[msgLen];
                    in.readFully(msgBytes);

                    String message = new String(msgBytes, StandardCharsets.UTF_8);
                    System.out.println("[SERVER] " + (status == 1 ? "SUCCESS: " : "ERROR: ") + message);

                    // Injeção de resposta bloqueia a variável global momentaneamente para assegurar atomicidade
                    app.setAuthStatus(status == 1, message);

                } else if (packetId == 17) {
                    // 0x11 Leaderboard Tick
                    byte numEntries = in.readByte();
                    java.util.List<String> newBoard = new java.util.ArrayList<>();

                    for (int i = 0; i < numEntries; i++) {
                        short nameLen = in.readShort();
                        byte[] nameBytes = new byte[nameLen];
                        in.readFully(nameBytes);
                        String name = new String(nameBytes, StandardCharsets.UTF_8);
                        int score = in.readInt();

                        newBoard.add(name + " - " + score + " Captures");
                    }
                    app.updateLeaderboard(newBoard);

                } else if (packetId == 18) {
                    int myPlayerId = in.readInt();
                    float mapWidth = in.readFloat();
                    float mapHeight = in.readFloat();

                    System.out.println("[SERVER] Game Started! My ID is: " + myPlayerId);
                    System.out.println("[SERVER] Map Dimensions: " + mapWidth + "x" + mapHeight);

                    app.setMyPlayerId(myPlayerId);
                } else if (packetId == 19) {
                    int numPlayers = in.readByte();

                    for (int i = 0; i < numPlayers; i++) {
                        int id = in.readInt();
                        float x = in.readFloat();
                        float y = in.readFloat();
                        float angle = in.readFloat();
                        float mass = in.readFloat();
                        int score = in.readInt();

                        app.gameState.updatePlayer(id, x, y, angle, mass, score);
                    }

                    short numObjects = in.readShort();
                    java.util.Map<Integer, GameApp.OrbData> newOrbs = new java.util.HashMap<>();

                    for (int i = 0; i < numObjects; i++) {
                        int id = in.readInt();
                        float x = in.readFloat();
                        float y = in.readFloat();
                        float radius = in.readFloat();
                        byte type = in.readByte();

                        newOrbs.put(id, app.new OrbData(id, x, y, radius, type));
                    }

                    app.gameState.updateObjects(newOrbs);

                } else if (packetId == 20) {
                    short nameLen = in.readShort();
                    byte[] nameBytes = new byte[nameLen];
                    in.readFully(nameBytes);
                    String winnerName = new String(nameBytes, StandardCharsets.UTF_8);
                    int score = in.readInt();

                    // Chama a função do monitor para mudar o ecrã
                    app.setMatchEnd(winnerName, score);

                } else {
                    System.out.println("Unknown packet ID: " + packetId);
                }
            }
        } catch (IOException e) {
            System.out.println("Disconnected from server.");
        }
    }
}