-- =============================================================
-- PROJECT: SemanticGraph-SQL (Symbolic AI Engine)
-- AUTHOR: [Giuseppe D'Ambrosio - Claudia Covucci]
-- DESCRIPTION: A relational framework for semantic analysis, 
--              KNN clustering, and vector distance in MySQL.
-- =============================================================

-- -------------------------------------------------------------
-- 1. DATABASE STRUCTURE (DDL)
-- -------------------------------------------------------------

CREATE TABLE etymology (
    id INT AUTO_INCREMENT PRIMARY KEY,
    etymon_root VARCHAR(100) NOT NULL,
    words_with_root VARCHAR(255) NOT NULL,
    words_with_meaning VARCHAR(255) NOT NULL
);

CREATE TABLE words (
    id INT AUTO_INCREMENT PRIMARY KEY,
    word VARCHAR(100) NOT NULL UNIQUE,
    meaning VARCHAR(255) NOT NULL,
    language VARCHAR(20) DEFAULT 'EN',
    word_synonyms VARCHAR(255), -- Legacy field
    etymology_id INT,
    category VARCHAR(50),
    FOREIGN KEY (etymology_id) REFERENCES etymology(id)
);

CREATE TABLE scenario (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scenario VARCHAR(100) NOT NULL UNIQUE,
    language VARCHAR(20) DEFAULT 'EN'
);

CREATE TABLE word_scenario (
    word_id INT NOT NULL,
    scenario_id INT NOT NULL,
    PRIMARY KEY (word_id, scenario_id),
    FOREIGN KEY (word_id) REFERENCES words(id),
    FOREIGN KEY (scenario_id) REFERENCES scenario(id)
);

CREATE TABLE verb (
    id INT AUTO_INCREMENT PRIMARY KEY,
    word_id INT NOT NULL UNIQUE,
    funzione VARCHAR(255) NOT NULL,
    FOREIGN KEY (word_id) REFERENCES words(id)
);

CREATE TABLE word_synonyms (
    word_id INT NOT NULL,
    synonym_word_id INT NOT NULL,
    PRIMARY KEY (word_id, synonym_word_id),
    FOREIGN KEY (word_id) REFERENCES words(id),
    FOREIGN KEY (synonym_word_id) REFERENCES words(id)
);

-- -------------------------------------------------------------
-- 2. MACHINE LEARNING LAYER (Weights & Vectors)
-- -------------------------------------------------------------

CREATE TABLE learning_weights (
    feature VARCHAR(50) PRIMARY KEY,
    weight INT DEFAULT 1
);

-- Inizializzazione pesi di default
INSERT IGNORE INTO learning_weights (feature, weight) VALUES 
('etymology', 5), 
('scenario', 2), 
('synonym', 3);

CREATE TABLE word_vector (
    word_id INT PRIMARY KEY,
    f_etymology INT,
    f_scenario_count INT,
    f_synonym_count INT,
    f_cluster_size INT,
    FOREIGN KEY (word_id) REFERENCES words(id)
);

-- Ottimizzazione indici
CREATE INDEX idx_words_etymology_id ON words(etymology_id);
CREATE INDEX idx_scenario_lookup ON word_scenario(word_id, scenario_id);
CREATE INDEX idx_synonym_lookup ON word_synonyms(word_id, synonym_word_id);

-- -------------------------------------------------------------
-- 3. SEMANTIC FUNCTIONS (Scoring & Classification)
-- -------------------------------------------------------------

DELIMITER //

-- Calcolo complessità semantica
CREATE FUNCTION semantic_score(word_input VARCHAR(100))
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE score INT DEFAULT 0;
    SELECT 
        1 
        + (CASE WHEN w.etymology_id IS NOT NULL THEN 1 ELSE 0 END)
        + COUNT(DISTINCT ws.scenario_id)
        + COUNT(DISTINCT w2.id)
    INTO score
    FROM words w
    LEFT JOIN words w2 ON w2.etymology_id = w.etymology_id AND w2.id != w.id
    LEFT JOIN word_scenario ws ON ws.word_id = w.id
    WHERE w.word = word_input
    GROUP BY w.id;
    RETURN COALESCE(score, 0);
END; //

-- Classificatore Decision Tree
CREATE FUNCTION decision_tree_class(word_input VARCHAR(100))
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE result_class VARCHAR(50);
    SELECT
        CASE
            WHEN v.word_id IS NOT NULL THEN 'Action Word (Verb)'
            WHEN w.etymology_id IS NULL AND (SELECT COUNT(*) FROM word_scenario WHERE word_id = w.id) = 0 THEN 'Primitive Concept'
            WHEN (SELECT COUNT(*) FROM word_scenario WHERE word_id = w.id) > 2 THEN 'Contextual Hub'
            WHEN (SELECT COUNT(*) FROM word_synonyms WHERE word_id = w.id) > 3 THEN 'Semantic Anchor'
            ELSE 'Basic Word'
        END
    INTO result_class
    FROM words w
    LEFT JOIN verb v ON v.word_id = w.id
    WHERE w.word = word_input;
    RETURN IFNULL(result_class, 'Unknown');
END; //

-- -------------------------------------------------------------
-- 4. ALGORITHMS (KNN & Vector Distance)
-- -------------------------------------------------------------

-- K-Nearest Neighbors (Weighted)
CREATE FUNCTION knn_evolved_w (word_input VARCHAR(100), k INT)
RETURNS JSON
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE neighbors JSON;
    DECLARE w_etymo INT DEFAULT 1;
    DECLARE w_scen INT DEFAULT 1;
    DECLARE w_syn INT DEFAULT 1;

    SELECT weight INTO w_etymo FROM learning_weights WHERE feature = 'etymology';
    SELECT weight INTO w_scen FROM learning_weights WHERE feature = 'scenario';
    SELECT weight INTO w_syn FROM learning_weights WHERE feature = 'synonym';

    SELECT JSON_ARRAYAGG(word)
    INTO neighbors
    FROM (
        SELECT w2.word,
               (
                   IF(w1.etymology_id = w2.etymology_id, w_etymo, 0)
                   + (SELECT COUNT(*) * w_scen FROM word_scenario ws1 
                      JOIN word_scenario ws2 ON ws1.scenario_id = ws2.scenario_id 
                      WHERE ws1.word_id = w1.id AND ws2.word_id = w2.id)
                   + (SELECT COUNT(*) * w_syn FROM word_synonyms s1 
                      JOIN word_synonyms s2 ON s1.synonym_word_id = s2.synonym_word_id 
                      WHERE s1.word_id = w1.id AND s2.word_id = w2.id)
               ) AS similarity
        FROM words w1
        INNER JOIN words w2 ON w1.id != w2.id
        WHERE w1.word = word_input
        HAVING similarity > 0
        ORDER BY similarity DESC
        LIMIT k
    ) AS t;
    RETURN neighbors;
END; //

-- Euclidean Distance (Vectorial Space)
CREATE FUNCTION vector_distance(word1 VARCHAR(100), word2 VARCHAR(100))
RETURNS DECIMAL(10,4)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE dist DECIMAL(10,4);
    SELECT SQRT(
        POW(v1.f_etymology - v2.f_etymology, 2) +
        POW(v1.f_scenario_count - v2.f_scenario_count, 2) +
        POW(v1.f_synonym_count - v2.f_synonym_count, 2) +
        POW(v1.f_cluster_size - v2.f_cluster_size, 2)
    )
    INTO dist
    FROM word_vector v1
    JOIN words w1 ON w1.id = v1.word_id
    CROSS JOIN word_vector v2 
    JOIN words w2 ON w2.id = v2.word_id
    WHERE w1.word = word1 AND w2.word = word2;
    RETURN dist;
END; //

-- -------------------------------------------------------------
-- 5. PROCEDURES & VIEWS
-- -------------------------------------------------------------

CREATE PROCEDURE sync_word_vectors()
BEGIN
    TRUNCATE TABLE word_vector;
    INSERT INTO word_vector (word_id, f_etymology, f_scenario_count, f_synonym_count, f_cluster_size)
    SELECT 
        w.id,
        CASE WHEN w.etymology_id IS NULL THEN 0 ELSE 1 END,
        (SELECT COUNT(*) FROM word_scenario ws WHERE ws.word_id = w.id),
        (SELECT COUNT(*) FROM word_synonyms s WHERE s.word_id = w.id),
        (SELECT COUNT(*) FROM words w2 WHERE w2.etymology_id = w.etymology_id AND w.etymology_id IS NOT NULL)
    FROM words w;
    SELECT 'SUCCESS: Word Vectors Synchronized' AS status;
END; //

DELIMITER ;

CREATE VIEW semantic_clusters AS
SELECT 
    e.etymon_root,
    GROUP_CONCAT(w.word SEPARATOR ', ') AS cluster_words,
    COUNT(w.id) AS cluster_size
FROM etymology e
JOIN words w ON e.id = w.etymology_id
GROUP BY e.id;



--sobel operator
CREATE FUNCTION detect_edge(pixel_x INT, pixel_y INT)
RETURNS DECIMAL(10,4)
DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE gx, gy DECIMAL(10,4);
    -- Semplificazione del Kernel di Sobel 3x3
    SELECT 
        SUM(p.brightness * k.val_x), SUM(p.brightness * k.val_y)
    INTO gx, gy
    FROM image_pixels p
    JOIN sobel_kernel k ON (p.x = pixel_x + k.dx AND p.y = pixel_y + k.dy)
    WHERE p.x BETWEEN pixel_x-1 AND pixel_x+1 
      AND p.y BETWEEN pixel_y-1 AND pixel_y+1;
      
    RETURN SQRT(POW(gx, 2) + POW(gy, 2));
END; //



---Hugh


CREATE PROCEDURE hough_transform_lines()
BEGIN
    -- Tabella di accumulazione per votare raggio e angolo
    INSERT INTO hough_accumulator (rho, theta, votes)
    SELECT 
        ROUND(x * COS(RADIANS(theta)) + y * SIN(RADIANS(theta))), 
        theta, 
        COUNT(*)
    FROM image_pixels
    CROSS JOIN (SELECT theta FROM angles_lookup) AS angles -- 0-180 gradi
    WHERE brightness > 200 -- Considera solo pixel luminosi (bordi)
    GROUP BY rho, theta
    HAVING votes > 50; -- Soglia per identificare una linea forte
END; //



---blob
CREATE VIEW detected_blobs AS
WITH RECURSIVE blob_search AS (
    -- Seed: pixel sopra una certa soglia
    SELECT x, y, CAST(CONCAT(x,',',y) AS CHAR(255)) AS blob_id
    FROM image_pixels WHERE brightness > 230 AND processed = 0
    UNION ALL
    -- Ricorsione: unisci i vicini
    SELECT p.x, p.y, b.blob_id
    FROM image_pixels p
    JOIN blob_search b ON (ABS(p.x - b.x) <= 1 AND ABS(p.y - b.y) <= 1)
    WHERE p.brightness > 230
)
SELECT blob_id, COUNT(*) as area, AVG(x) as center_x, AVG(y) as center_y
FROM blob_search GROUP BY blob_id;

---eye detection


CREATE FUNCTION detect_eye_region(x INT, y INT, w INT, h INT)
RETURNS DECIMAL(10,4)
DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE upper_rect, lower_rect INT;
    -- Calcola la somma di luminosità di due rettangoli sovrapposti
    SET upper_rect = (SELECT SUM(brightness) FROM image_pixels WHERE x BETWEEN x AND x+w AND y BETWEEN y AND y+(h/2));
    SET lower_rect = (SELECT SUM(brightness) FROM image_pixels WHERE x BETWEEN x AND x+w AND y BETWEEN y+(h/2) AND y+h);
    
    -- Se la parte superiore (occhio) è molto più scura della inferiore (guancia/naso)
    RETURN (lower_rect - upper_rect);
END; //


---ransac

-- Esempio logico di un'iterazione RANSAC per una linea
CREATE PROCEDURE ransac_step()
BEGIN
    -- Prendi 2 punti a caso e calcola pendenza (m) e intercetta (q)
    -- Conta quanti altri punti pixel distano meno di 'epsilon' da quella linea
    SELECT COUNT(*) INTO @inliers
    FROM image_pixels
    WHERE ABS(y - (@m * x + @q)) < 0.5;
END; //



CREATE TABLE training_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    word1_id INT,
    word2_id INT,
    expected_similarity INT, -- 0 = diverso, 1 = simile
    source VARCHAR(50), -- 'manual', 'user', 'system'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (word1_id) REFERENCES words(id),
    FOREIGN KEY (word2_id) REFERENCES words(id)
);


CREATE TABLE feedback_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    word_input VARCHAR(100),
    suggested_word VARCHAR(100),
    feedback_score INT, -- +1 corretto, -1 errato
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE model_error (
    id INT AUTO_INCREMENT PRIMARY KEY,
    word1_id INT,
    word2_id INT,
    predicted_score DECIMAL(10,4),
    expected_score INT,
    error DECIMAL(10,4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


DELIMITER //

CREATE FUNCTION compute_similarity(word1 VARCHAR(100), word2 VARCHAR(100))
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE sim INT;

    SELECT 
        IF(w1.etymology_id = w2.etymology_id, 1, 0)
        + (SELECT COUNT(*) FROM word_scenario ws1 
           JOIN word_scenario ws2 
           ON ws1.scenario_id = ws2.scenario_id
           WHERE ws1.word_id = w1.id AND ws2.word_id = w2.id)
        + (SELECT COUNT(*) FROM word_synonyms s1 
           JOIN word_synonyms s2 
           ON s1.synonym_word_id = s2.synonym_word_id
           WHERE s1.word_id = w1.id AND s2.word_id = w2.id)
    INTO sim
    FROM words w1, words w2
    WHERE w1.word = word1 AND w2.word = word2;

    RETURN IFNULL(sim, 0);
END //

DELIMITER ;


DELIMITER //

CREATE PROCEDURE train_step()
BEGIN
    INSERT INTO model_error (word1_id, word2_id, predicted_score, expected_score, error)
    SELECT 
        td.word1_id,
        td.word2_id,
        compute_similarity(w1.word, w2.word),
        td.expected_similarity,
        ABS(compute_similarity(w1.word, w2.word) - td.expected_similarity)
    FROM training_data td
    JOIN words w1 ON w1.id = td.word1_id
    JOIN words w2 ON w2.id = td.word2_id;
END //

DELIMITER ;



DELIMITER //

CREATE PROCEDURE update_weights()
BEGIN
    DECLARE avg_error DECIMAL(10,4);

    SELECT AVG(error) INTO avg_error FROM model_error;

    -- Se errore alto → aumenta peso etimologia
    IF avg_error > 1 THEN
        UPDATE learning_weights 
        SET weight = weight + 1
        WHERE feature = 'etymology';
    END IF;

    -- Feedback utente influenza i pesi
    UPDATE learning_weights lw
    JOIN (
        SELECT AVG(feedback_score) AS avg_fb
        FROM feedback_log
    ) f
    SET lw.weight = lw.weight + f.avg_fb
    WHERE lw.feature = 'synonym';
END //

DELIMITER ;


DELIMITER //

CREATE PROCEDURE training_loop()
BEGIN
    CALL train_step();
    CALL update_weights();

    -- Reset error per prossimo ciclo
    DELETE FROM model_error;
END //

DELIMITER ;



INSERT INTO training_data (word1_id, word2_id, expected_similarity, source)
SELECT w1.id, w2.id, 1, 'system'
FROM words w1
JOIN words w2 
ON w1.etymology_id = w2.etymology_id
WHERE w1.id != w2.id;


CREATE TABLE neuron_state (
    word_id INT PRIMARY KEY,
    activation DECIMAL(10,6) DEFAULT 0,
    bias DECIMAL(10,6) DEFAULT 0,
    FOREIGN KEY (word_id) REFERENCES words(id)
);
--UPDATE neuron_state ns
--JOIN words w ON w.id = ns.word_id
--SET ns.activation = 1.0
--WHERE w.word IN ('cliente', 'attivo');



UPDATE neuron_state ns_target
JOIN (
    SELECT 
        ws2.word_id AS target_id,
        SUM(ns.activation * lw.weight) AS new_activation
    FROM neuron_state ns
    JOIN word_scenario ws1 ON ws1.word_id = ns.word_id
    JOIN word_scenario ws2 ON ws1.scenario_id = ws2.scenario_id
    JOIN learning_weights lw ON lw.feature = 'scenario'
    GROUP BY ws2.word_id
) calc ON ns_target.word_id = calc.target_id
SET ns_target.activation = ns_target.activation + calc.new_activation;



UPDATE neuron_state ns
JOIN (
    SELECT word_id, SUM(score) AS total
    FROM (

        -- etymology
        SELECT w2.id AS word_id, lw.weight * ns.activation AS score
        FROM neuron_state ns
        JOIN words w1 ON w1.id = ns.word_id
        JOIN words w2 ON w1.etymology_id = w2.etymology_id
        JOIN learning_weights lw ON lw.feature = 'etymology'

        UNION ALL

        -- scenario
        SELECT ws2.word_id, lw.weight * ns.activation
        FROM neuron_state ns
        JOIN word_scenario ws1 ON ws1.word_id = ns.word_id
        JOIN word_scenario ws2 ON ws1.scenario_id = ws2.scenario_id
        JOIN learning_weights lw ON lw.feature = 'scenario'

        UNION ALL

        -- synonyms
        SELECT s.synonym_word_id, lw.weight * ns.activation
        FROM neuron_state ns
        JOIN word_synonyms s ON s.word_id = ns.word_id
        JOIN learning_weights lw ON lw.feature = 'synonym'

    ) t
    GROUP BY word_id
) agg ON ns.word_id = agg.word_id
SET ns.activation = agg.total;



UPDATE neuron_state
SET activation = 1 / (1 + EXP(-activation));




CREATE TABLE neuron_error (
    word_id INT,
    error DECIMAL(10,6)
);


UPDATE neuron_error ne
JOIN neuron_state ns ON ns.word_id = ne.word_id
SET ne.error = ns.activation - expected;


UPDATE learning_weights
SET weight = weight - 0.01 * (
    SELECT AVG(error) FROM neuron_error
);
