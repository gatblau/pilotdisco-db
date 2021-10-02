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
        ---------------------------------------------------------------------------
        -- Control (store the various discoverable pilot control services)
        ---------------------------------------------------------------------------
        IF NOT EXISTS(SELECT relname FROM pg_class WHERE relname = 'control')
        THEN
            CREATE SEQUENCE control_id_seq
                INCREMENT 1
                START 1000
                MINVALUE 1000
                MAXVALUE 9223372036854775807
                CACHE 1;

            ALTER SEQUENCE control_id_seq
                OWNER TO pilotdisco;

            CREATE TABLE "control"
            (
                -- the control table surrogate key
                id          BIGINT                 NOT NULL DEFAULT nextval('control_id_seq'::regclass),
                -- the name of the pilot control service
                name        CHARACTER VARYING(100) NOT NULL,
                -- provides additional information about the specific pilot control service
                description CHARACTER VARYING(250),
                -- the URI of the pilot control service
                uri         CHARACTER VARYING(150),
                -- the encrypted username to log in the pilot control service
                username    CHARACTER VARYING(150),
                -- the encrypted password to log in the pilot control service
                pwd         CHARACTER VARYING(300),
                -- the encrypted pgp public key for the pilot control service
                pub         CHARACTER VARYING(500),
                -- the salt for the encrypted secrets
                salt        CHARACTER VARYING(300),
                -- the primary key constraint for the table surrogate key
                CONSTRAINT control_id_pk PRIMARY KEY (id),
                -- forces the name column to be unique
                CONSTRAINT control_name_uc UNIQUE (name)
            ) WITH (OIDS = FALSE)
              TABLESPACE pg_default;

            ALTER TABLE "control"
                OWNER to pilotdisco;
        END IF;

        ---------------------------------------------------------------------------
        -- Host (store the host information for automated admittance to the allocated pilot control service)
        ---------------------------------------------------------------------------
        IF NOT EXISTS(SELECT relname FROM pg_class WHERE relname = 'admission')
        THEN
            CREATE SEQUENCE admission_id_seq
                INCREMENT 1
                START 1000
                MINVALUE 1000
                MAXVALUE 9223372036854775807
                CACHE 1;

            ALTER SEQUENCE admission_id_seq
                OWNER TO pilotdisco;

            CREATE TABLE "admission"
            (
                -- the control table surrogate key
                id                BIGINT                 NOT NULL DEFAULT nextval('admission_id_seq'::regclass),
                -- a hashed token identifying the the first mac address of the host to admit
                -- the hash is made of the mac address and an access token shared between pilot and pilot discovery
                mac_address_token CHARACTER VARYING(100) NOT NULL,
                -- the host universally unique identifier (populated upon admittance)
                host_uuid         CHARACTER VARYING(20),
                -- the org group to be allocated to the host upon admission
                org_group         CHARACTER VARYING(50) NOT NULL,
                -- the org to be allocated to the host upon admission
                org               CHARACTER VARYING(50) NOT NULL,
                -- the area to be allocated to the host upon admission
                area              CHARACTER VARYING(50) NOT NULL,
                -- the location to be allocated to the host upon admission
                location          CHARACTER VARYING(50) NOT NULL,
                -- the date the admission has occurred (populated upon admittance)
                admitted          TIMESTAMP(6) WITH TIME ZONE,
                -- discovered host information (populated upon admittance)
                host_info         JSONB,
                -- the foreign key to the pilot control service to use
                control_id        BIGINT NOT NULL,
                -- the primary key constraint for the table surrogate key
                CONSTRAINT admission_id_pk PRIMARY KEY (id),
                -- forces the host_uuid column to be unique
                CONSTRAINT admission_host_uuid_uc UNIQUE (host_uuid),
                -- forces the mac_address_token column to be unique
                CONSTRAINT admission_mac_address_token_uc UNIQUE (mac_address_token),
                -- foreign key to control table
                CONSTRAINT control_id_fk FOREIGN KEY (control_id)
                    REFERENCES control (id) MATCH SIMPLE
                    ON UPDATE NO ACTION
                    ON DELETE CASCADE
            ) WITH (OIDS = FALSE)
              TABLESPACE pg_default;

            ALTER TABLE "admission"
                OWNER to pilotdisco;
        END IF;

    END;
$$
