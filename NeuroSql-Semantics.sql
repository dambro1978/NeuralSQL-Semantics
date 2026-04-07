-- =============================================================
-- PROJECT: SemanticGraph-SQL (Symbolic AI Engine)
-- AUTHOR: [Giuseppe D'Ambrosio - Claudia Covucci]
-- DESCRIPTION: A relational framework for semantic analysis, 
--              KNN clustering, and vector distance in MySQL.
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
