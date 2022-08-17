@preprocessor typescript
@{%
import LexerAdapter from 'src/grammar/LexerAdapter';
import { NodeType } from 'src/parser/ast';

// The lexer here is only to provide the has() method,
// that's used inside the generated grammar definition.
// A proper lexer gets passed to Nearley Parser constructor.
const lexer = new LexerAdapter(chunk => []);

const flatten = (arr: any[]) => arr.flat(Infinity);
%}
@lexer lexer

# This postprocessor is quite complex.
# Might be better to eliminate hasSemicolon field
# and allow for empty statement in the end,
# so semicolons could then be placed between each statement.
main -> statement (%DELIMITER statement):* {%
  (items) => {
    return flatten(items)
      // skip semicolons
      .filter(item => item.type === NodeType.statement)
      // mark all statements except the last as having a semicolon
      .map((statement, i, allStatements) => {
        if (i === allStatements.length - 1) {
          return { ...statement, hasSemicolon: false };
        } else {
          return { ...statement, hasSemicolon: true };
        }
      })
      // throw away last statement if it's empty
      .filter(({children, hasSemicolon}) => hasSemicolon || children.length > 0);
  }
%}

statement -> expressions_or_clauses {%
  (children) => ({
    type: NodeType.statement,
    children: flatten(children),
  })
%}

# To avoid ambiguity, plain expressions can only come before clauses
expressions_or_clauses -> expression:* clause:*

clause -> limit_clause | other_clause

limit_clause -> %LIMIT expression (%COMMA expression):? {%
  // TODO: allow more than single node for exp1 & exp2
  ([limitToken, exp1, optional]) => {
    if (optional) {
      const [comma, exp2] = optional;
      return {
        type: NodeType.limit_clause,
        limitToken,
        offset: exp1,
        count: exp2,
      };
    } else {
      return {
        type: NodeType.limit_clause,
        limitToken,
        count: exp1,
      };
    }
  }
%}

other_clause -> %RESERVED_COMMAND expression:* {%
  ([nameToken, children]) => ({
    type: NodeType.clause,
    nameToken,
    children: flatten(children),
  })
%}

expression -> array_subscript | function_call| parenthesis | plain_token

array_subscript -> (%IDENTIFIER | %RESERVED_KEYWORD) "[" expression:* "]" {%
  ([[arrayToken], open, children, close]) => ({
    type: NodeType.array_subscript,
    arrayToken,
    parenthesis: {
      type: NodeType.parenthesis,
      children: flatten(children),
      openParen: "[",
      closeParen: "]",
    },
  })
%}

function_call -> %RESERVED_FUNCTION_NAME parenthesis {%
  ([name, parens]) => ({
    type: NodeType.function_call,
    nameToken: name,
    parenthesis: parens,
  })
%}

parenthesis -> "(" expressions_or_clauses ")" {%
  ([open, children, close]) => ({
    type: NodeType.parenthesis,
    children: flatten(children),
    openParen: "(",
    closeParen: ")",
  })
%}

plain_token ->
  ( %IDENTIFIER
  | %QUOTED_IDENTIFIER
  | %STRING
  | %VARIABLE
  | %RESERVED_KEYWORD
  | %RESERVED_PHRASE
  | %RESERVED_DEPENDENT_CLAUSE
  | %RESERVED_SET_OPERATION
  | %RESERVED_JOIN
  | %CASE
  | %END
  | %BETWEEN
  | %AND
  | %OR
  | %XOR
  | %LINE_COMMENT
  | %BLOCK_COMMENT
  | %NUMBER
  | %NAMED_PARAMETER
  | %QUOTED_PARAMETER
  | %NUMBERED_PARAMETER
  | %POSITIONAL_PARAMETER
  | %COMMA
  | %OPERATOR ) {%
  ([[token]]) => ({ type: NodeType.token, token })
%}
