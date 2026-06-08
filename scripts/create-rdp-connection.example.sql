-- Example PostgreSQL script for creating an enhanced Guacamole RDP connection.
-- Run inside the Guacamole PostgreSQL database.
--
-- Example:
--   docker exec -i guac-postgres psql -U guacamole_user -d guacamole_db < scripts/create-rdp-connection.example.sql
--
-- Adjust connection_name, hostname, port, drive-path, and permission entity_id
-- before using this in production.

DO $$
DECLARE
    cid integer;
BEGIN
    SELECT connection_id INTO cid
    FROM guacamole_connection
    WHERE connection_name = 'PC-1';

    IF cid IS NULL THEN
        INSERT INTO guacamole_connection (
            connection_name,
            parent_id,
            protocol,
            max_connections,
            max_connections_per_user,
            connection_weight,
            failover_only,
            proxy_port,
            proxy_hostname,
            proxy_encryption_method
        ) VALUES (
            'PC-1',
            NULL,
            'rdp',
            NULL,
            NULL,
            1,
            FALSE,
            NULL,
            NULL,
            'NONE'
        )
        RETURNING connection_id INTO cid;
    END IF;

    DELETE FROM guacamole_connection_parameter WHERE connection_id = cid;

    INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
        (cid, 'hostname', '127.0.0.1'),
        (cid, 'port', '13389'),
        (cid, 'security', 'nla'),
        (cid, 'ignore-cert', 'true'),
        (cid, 'resize-method', 'display-update'),
        (cid, 'color-depth', '24'),

        -- Performance defaults.
        (cid, 'enable-wallpaper', 'false'),
        (cid, 'enable-theming', 'true'),
        (cid, 'enable-full-window-drag', 'false'),
        (cid, 'enable-desktop-composition', 'false'),
        (cid, 'enable-menu-animations', 'false'),

        -- File transfer through Guacamole's virtual RDP drive.
        (cid, 'enable-drive', 'true'),
        (cid, 'drive-name', 'Guacamole Drive'),
        (cid, 'drive-path', '/guacdrive/pc1'),
        (cid, 'create-drive-path', 'true'),
        (cid, 'disable-download', 'false'),
        (cid, 'disable-upload', 'false'),

        -- Remote audio playback in the browser. Enable microphone only when needed.
        (cid, 'disable-audio', 'false'),
        (cid, 'enable-audio-input', 'false'),

        -- Clipboard is enabled by default. Windows RDP expects CRLF line endings.
        (cid, 'normalize-clipboard', 'windows');

    -- Entity 1 is commonly the first admin user in a fresh Guacamole database.
    -- Replace it if your target user/entity differs.
    INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
    SELECT 1, cid, perm::guacamole_object_permission_type
    FROM (VALUES ('READ'), ('UPDATE'), ('DELETE'), ('ADMINISTER')) AS perms(perm)
    ON CONFLICT DO NOTHING;
END $$;

SELECT connection_id, connection_name, protocol
FROM guacamole_connection
WHERE connection_name = 'PC-1';

SELECT parameter_name, parameter_value
FROM guacamole_connection_parameter
WHERE connection_id = (
    SELECT connection_id
    FROM guacamole_connection
    WHERE connection_name = 'PC-1'
)
ORDER BY parameter_name;
