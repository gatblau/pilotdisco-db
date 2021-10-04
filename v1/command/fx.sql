/*
    Onix Pilot Discovery Service - Copyright (c) 2018-2021 by www.gatblau.org

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software distributed under
    the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
    either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

    Contributors to this project, hereby assign copyright in this code to the project,
    to be licensed under the same terms as the rest of the code.
*/
DO
$$
    BEGIN
        /*
      Encapsulates the logic to determine the status of a record update:
        - N: no update as no changes found - new and old records are the same
        - L: no update as the old record was updated by another client before this update could be committed
        - U: update - the record was updated successfully
     */
        CREATE OR REPLACE FUNCTION pilotdisco_get_update_status(
            current_version bigint, -- the version of the record in the database
            local_version bigint, -- the version in the new specified record
            updated boolean -- whether or not the record was updated in the database by the last update statement
        )
            RETURNS char(1)
            LANGUAGE 'plpgsql'
            COST 100
            STABLE
        AS
        $BODY$
        DECLARE
            result char(1);
        BEGIN
            -- if there were not rows affected
            IF NOT updated THEN
                -- if the local version is the same as the record version
                -- or no version is passed (NULL) or a zero value is passed (less than 1)
                IF (local_version = current_version OR local_version IS NULL OR local_version = 0) THEN
                    -- no update was required as required record was the same as stored record
                    result := 'N';
                ELSE
                    -- no update was made as stored record is optimistically locked
                    -- i.e. updated by other client before this update can be committed
                    result := 'L';
                END IF;
            ELSE
                -- the stored record was updated successfully
                result := 'U';
            END IF;

            RETURN result;
        END;
        $BODY$;

        ALTER FUNCTION pilotdisco_get_update_status(bigint, bigint, boolean)
            OWNER TO pilotdisco;

        -----------------------------------------------------------------------------------------
        -- pilotdisco_set_control() create or update a control record
        -----------------------------------------------------------------------------------------
        CREATE OR REPLACE FUNCTION pilotdisco_set_control(
            name_param CHARACTER VARYING,
            description_param CHARACTER VARYING,
            uri_param CHARACTER VARYING,
            username_param CHARACTER VARYING,
            pwd_param CHARACTER VARYING,
            pub_param CHARACTER VARYING,
            salt_param CHARACTER VARYING,
            local_version_param BIGINT,
            changed_by_param CHARACTER VARYING)
            RETURNS TABLE
                    (
                        result char(1)
                    )
            LANGUAGE 'plpgsql'
            COST 100
            VOLATILE
        AS
        $BODY$
        DECLARE
            result          char(1); -- the result status for the upsert
            current_version bigint; -- the version of the row before the update or null if no row
            rows_affected   integer;
            new_salt        character varying;
        BEGIN
            -- gets the current control record version
            SELECT version FROM control WHERE name = name_param INTO current_version;

            IF (current_version IS NULL) THEN
                INSERT INTO "control" (id,
                                       name,
                                       description,
                                       uri,
                                       username,
                                       pwd,
                                       pub,
                                       salt,
                                       version,
                                       created,
                                       updated,
                                       changed_by)
                VALUES (nextval('control_id_seq'),
                        name_param,
                        description_param,
                        uri_param,
                        username_param,
                        pwd_param,
                        pub_param,
                        salt_param,
                        1,
                        current_timestamp,
                        current_timestamp,
                        changed_by_param);
                result := 'I';
            ELSE
                -- NOTE: if a password has been provided, even if it is the same as the originally
                -- stored in the database, it would have got here encrypted with a new randomly generated
                -- salt and therefore, it would look different to the database server
                -- so it would get updated and would look different both pwd and salt in the database
                IF (pwd_param IS NOT NULL) THEN
                    -- has to update the salt otherwise the app will not be able to decrypt
                    -- the new secrets in the future
                    new_salt = salt_param;
                END IF;

                UPDATE "control"
                SET name        = name_param,
                    description = description_param,
                    uri         = uri_param,
                    username    = username_param,
                    pwd         = COALESCE(pwd_param, pwd), -- if the passed-in password is NULL, then do not change it
                    pub         = COALESCE(pub_param, pub), -- if the passed-in key is NULL, then do not change it
                    salt        = COALESCE(new_salt, salt), -- if new_salt is NOT NULL, then update the salt
                    version     = version + 1,
                    updated     = current_timestamp,
                    changed_by  = changed_by_param
                WHERE name = name_param
                  -- concurrency management - optimistic locking
                  AND (local_version_param = current_version OR local_version_param IS NULL OR local_version_param = 0)
                  AND (
                            name != name_param OR
                            description != description_param OR
                            uri != uri_param OR
                            username != username_param OR
                            (pwd != pwd_param AND pwd_param IS NOT NULL) OR
                            (pub != pub_param AND pub_param IS NOT NULL)
                    );
                GET DIAGNOSTICS rows_affected := ROW_COUNT;
                SELECT pilotdisco_get_update_status(current_version, local_version_param, rows_affected > 0)
                INTO result;
            END IF;
        END ;
        $BODY$;

        -----------------------------------------------------------------------------------------
        -- pilotdisco_set_admission() create or update a admission record
        -----------------------------------------------------------------------------------------
        CREATE OR REPLACE FUNCTION pilotdisco_set_admission(
            ref_param CHARACTER VARYING,
            mac_address_param CHARACTER VARYING,
            org_group_param CHARACTER VARYING,
            org_param CHARACTER VARYING,
            area_param CHARACTER VARYING,
            location_param CHARACTER VARYING,
            control_id_param BIGINT,
            control_version_param BIGINT,
            local_version_param BIGINT,
            changed_by_param CHARACTER VARYING)
            RETURNS TABLE
                    (
                        result char(1)
                    )
            LANGUAGE 'plpgsql'
            COST 100
            VOLATILE
        AS
        $BODY$
        DECLARE
            result          char(1); -- the result status for the upsert
            current_version bigint; -- the version of the row before the update or null if no row
            rows_affected   integer;
        BEGIN
            -- gets the current control record version
            SELECT version FROM admission WHERE mac_address = mac_address_param INTO current_version;

            IF (current_version IS NULL) THEN
                INSERT INTO "admission" (id,
                                         ref,
                                         mac_address,
                                         org_group,
                                         org,
                                         area,
                                         location,
                                         control_id,
                                         control_version,
                                         version,
                                         created,
                                         updated,
                                         changed_by)
                VALUES (nextval('admission_id_seq'),
                        ref_param,
                        mac_address_param,
                        org_group_param,
                        org_param,
                        area_param,
                        location_param,
                        control_id_param,
                        control_version_param,
                        1,
                        CURRENT_TIMESTAMP,
                        CURRENT_TIMESTAMP,
                        changed_by_param);
                result := 'I';
            ELSE
                UPDATE "admission"
                SET ref             = ref_param,
                    org_group       = org_group_param,
                    org             = org_param,
                    area            = area_param,
                    location        = location_param,
                    control_id      = control_id_param,
                    control_version = control_version_param,
                    version         = version + 1,
                    updated         = current_timestamp,
                    changed_by      = changed_by_param
                WHERE mac_address = mac_address_param
                  -- concurrency management - optimistic locking
                  AND (local_version_param = current_version OR local_version_param IS NULL OR local_version_param = 0)
                  AND (
                            ref != ref_param OR
                            org_group != org_group_param OR
                            org != org_param OR
                            area != area_param OR
                            location != location_param OR
                            control_id != control_id_param OR
                            control_version != control_version_param
                    );
                GET DIAGNOSTICS rows_affected := ROW_COUNT;
                SELECT pilotdisco_get_update_status(current_version, local_version_param, rows_affected > 0)
                INTO result;
            END IF;
        END ;
        $BODY$;

        -----------------------------------------------------------------------------------------
        -- pilotdisco_set_admitted() set the admission record for a mac_address to admitted
        -- and add host specific information
        -----------------------------------------------------------------------------------------
        CREATE OR REPLACE FUNCTION pilotdisco_set_control(
            mac_address_param CHARACTER VARYING,
            host_uuid_param CHARACTER VARYING,
            host_info_param CHARACTER VARYING,
            local_version_param BIGINT,
            changed_by_param CHARACTER VARYING)
            RETURNS TABLE
                    (
                        result char(1)
                    )
            LANGUAGE 'plpgsql'
            COST 100
            VOLATILE
        AS
        $BODY$
        DECLARE
            already_admitted BOOLEAN;
            result           CHAR(1); -- the result status for the upsert
            current_version  BIGINT; -- the version of the row before the update or null if no row
            rows_affected    INTEGER;
        BEGIN
            -- gets the current control record version
            SELECT version, admitted
            FROM admission
            WHERE mac_address = mac_address_param
            INTO current_version, already_admitted;

            -- only updates the record if it has not been already admitted
            IF NOT already_admitted THEN
                UPDATE "admission"
                SET host_uuid  = host_uuid_param,
                    admitted   = TRUE,
                    host_info  = host_info_param,
                    version    = version + 1,
                    updated    = current_timestamp,
                    changed_by = changed_by_param
                WHERE mac_address = mac_address_param
                  -- concurrency management - optimistic locking
                  AND (local_version_param = current_version OR local_version_param IS NULL OR
                       local_version_param = 0)
                  AND (
                            host_uuid != host_uuid_param OR
                            admitted != TRUE OR
                            host_info != host_info_param
                    );
            ELSE
                RAISE EXCEPTION 'Host with mac address % is already admitted.', mac_address_param
                    USING hint = 'Admission can only be done once.';
            END IF;

            -- prepares the update result
            GET DIAGNOSTICS rows_affected := ROW_COUNT;
            SELECT pilotdisco_get_update_status(current_version, local_version_param, rows_affected > 0) INTO result;
        END;
        $BODY$;

        -----------------------------------------------------------------------------------------
        -- pilotdisco_get_control() get one or all control records (if name_param = NULL)
        -----------------------------------------------------------------------------------------
        CREATE OR REPLACE FUNCTION pilotdisco_get_control(
            name_param CHARACTER VARYING
        )
            RETURNS TABLE
                    (
                        id          BIGINT,
                        name        CHARACTER VARYING,
                        description CHARACTER VARYING,
                        uri         CHARACTER VARYING,
                        username    CHARACTER VARYING,
                        pwd         CHARACTER VARYING,
                        pub         CHARACTER VARYING,
                        salt        CHARACTER VARYING,
                        version     BIGINT,
                        created     TIMESTAMP(6) WITH TIME ZONE,
                        updated     TIMESTAMP(6) WITH TIME ZONE,
                        changed_by  CHARACTER VARYING
                    )
            LANGUAGE 'plpgsql'
            COST 100
            STABLE
        AS
        $BODY$
        BEGIN
            SELECT id,
                   name,
                   description,
                   uri,
                   username,
                   pwd,
                   pub,
                   salt,
                   version,
                   created,
                   updated,
                   changed_by
            FROM control
            WHERE name = COALESCE(name_param, name);
        END;
        $BODY$;

        -----------------------------------------------------------------------------------------
        -- pilotdisco_get_admission() get one or all admission records (if mac_address_param = NULL)
        -----------------------------------------------------------------------------------------
        CREATE OR REPLACE FUNCTION pilotdisco_get_admission(
            mac_address_param CHARACTER VARYING,
            control_name_param CHARACTER VARYING
        )
            RETURNS TABLE
                    (
                        id              BIGINT,
                        ref             CHARACTER VARYING,
                        mac_address     CHARACTER VARYING,
                        host_uuid       CHARACTER VARYING,
                        org_group       CHARACTER VARYING,
                        org             CHARACTER VARYING,
                        area            CHARACTER VARYING,
                        location        CHARACTER VARYING,
                        admitted        BOOLEAN,
                        host_info       JSONB,
                        control_name    CHARACTER VARYING,
                        control_id      BIGINT,
                        control_version BIGINT,
                        created         TIMESTAMP(6) WITH TIME ZONE,
                        updated         TIMESTAMP(6) WITH TIME ZONE,
                        changed_by      CHARACTER VARYING
                    )
            LANGUAGE 'plpgsql'
            COST 100
            STABLE
        AS
        $BODY$
        BEGIN
            SELECT a.id,
                   a.mac_address,
                   a.host_uuid,
                   a.org_group,
                   a.org,
                   a.area,
                   a.location,
                   a.admitted,
                   a.host_info,
                   c.name as control_name,
                   a.control_id,
                   a.control_version,
                   a.version,
                   a.created,
                   a.updated,
                   a.changed_by
            FROM admission a
                     INNER JOIN control c on a.control_id = c.id
            WHERE a.mac_address = COALESCE(mac_address_param, a.mac_address)
              AND c.name = COALESCE(control_name_param, c.name);
        END;
        $BODY$;
    END ;
$$